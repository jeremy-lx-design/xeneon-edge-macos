//
// xeneonctl - a tiny command-line tool for controlling screen settings
// (brightness, contrast, volume, mute, input) on a CORSAIR XENEON EDGE,
// or any other DDC/CI-capable external display, on Windows.
//
// It talks DDC/CI through the standard Windows Monitor Configuration API
// (Dxva2.dll). No drivers, daemons or third-party libraries required.
//
// Build:  make        (see the Makefile; MinGW-w64 gcc or MSVC cl)
//
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601  // QueryDisplayConfig needs Windows 7 or newer.
#include <windows.h>
#include <physicalmonitorenumerationapi.h>
#include <lowlevelmonitorconfigurationapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// DDC/CI (VESA MCCS) VCP codes.
typedef struct {
    const char *name;
    BYTE vcpCode;
} Setting;

static const Setting kSettings[] = {
    {"brightness", 0x10},
    {"contrast",   0x12},
    {"volume",     0x62},
    {"mute",       0x8D},
    {"input",      0x60},
};
#define kSettingsCount (sizeof(kSettings) / sizeof(kSettings[0]))

static const char *kDefaultDisplayNameMatch = "XENEON";

// ---------- Helpers ----------

static void die(const char *message) {
    fprintf(stderr, "%s\n", message);
    exit(EXIT_FAILURE);
}

static const Setting *settingNamed(const char *name) {
    for (size_t i = 0; i < kSettingsCount; i++) {
        if (_stricmp(name, kSettings[i].name) == 0)
            return &kSettings[i];
    }
    return NULL;
}

// Case-insensitive substring test (the CRT has no portable strcasestr).
static BOOL containsIgnoreCase(const char *haystack, const char *needle) {
    size_t needleLen = strlen(needle);
    if (needleLen == 0) return TRUE;
    for (const char *p = haystack; *p; p++) {
        if (_strnicmp(p, needle, needleLen) == 0) return TRUE;
    }
    return FALSE;
}

static void printUsage(void) {
    printf(
        "xeneonctl - control screen settings on the CORSAIR XENEON EDGE (or any\n"
        "DDC/CI display) on Windows.\n"
        "\n"
        "Usage:\n"
        "  xeneonctl list                    List DDC-controllable displays\n"
        "  xeneonctl get <setting>            Read current (and max) value\n"
        "  xeneonctl set <setting> <value>    Write a new value\n"
        "\n"
        "Settings: brightness, contrast, volume, mute, input\n"
        "  brightness/contrast/volume - typically 0-100\n"
        "  mute                       - on/off (or 1/0)\n"
        "  input                      - VCP input select code (varies by display)\n"
        "\n"
        "Examples:\n"
        "  xeneonctl get brightness\n"
        "  xeneonctl set brightness 60\n"
        "  xeneonctl set mute on\n"
        "\n"
        "By default xeneonctl targets the first connected external display whose\n"
        "name contains \"XENEON\"; if none is found it falls back to the first\n"
        "non-built-in display. Run 'xeneonctl list' to see what was detected.\n"
    );
}

// ---------- Display discovery ----------

#define MAX_DISPLAYS  16
#define NAME_BUF_SIZE 128

typedef struct {
    PHYSICAL_MONITOR physMon;
    char productName[NAME_BUF_SIZE];
    BOOL isBuiltin;
} DisplayInfo;

static int gDisplayCount = 0;
static DisplayInfo gDisplays[MAX_DISPLAYS];

// Windows reports a physical monitor's description as something generic
// ("Generic PnP Monitor") far more often than not, which is useless for
// matching on "XENEON". The display-config API exposes the real EDID name
// and whether the panel is internal, so look the monitor up there by its
// device path and fall back to the generic description only if that fails.
static void lookupMonitorIdentity(const char *gdiDeviceName, char *nameOut, size_t nameOutSize, BOOL *isBuiltinOut) {
    DISPLAY_DEVICEA monitorDevice;
    memset(&monitorDevice, 0, sizeof(monitorDevice));
    monitorDevice.cb = sizeof(monitorDevice);
    // EDD_GET_DEVICE_INTERFACE_NAME makes DeviceID the monitor's device
    // path, which is what the display-config targets are keyed by.
    if (!EnumDisplayDevicesA(gdiDeviceName, 0, &monitorDevice, EDD_GET_DEVICE_INTERFACE_NAME))
        return;

    UINT32 pathCount = 0, modeCount = 0;
    if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS)
        return;

    DISPLAYCONFIG_PATH_INFO *paths = calloc(pathCount, sizeof(DISPLAYCONFIG_PATH_INFO));
    DISPLAYCONFIG_MODE_INFO *modes = calloc(modeCount, sizeof(DISPLAYCONFIG_MODE_INFO));
    if (!paths || !modes) {
        free(paths);
        free(modes);
        return;
    }

    if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths, &modeCount, modes, NULL) == ERROR_SUCCESS) {
        for (UINT32 i = 0; i < pathCount; i++) {
            DISPLAYCONFIG_TARGET_DEVICE_NAME target;
            memset(&target, 0, sizeof(target));
            target.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            target.header.size = sizeof(target);
            target.header.adapterId = paths[i].targetInfo.adapterId;
            target.header.id = paths[i].targetInfo.id;
            if (DisplayConfigGetDeviceInfo(&target.header) != ERROR_SUCCESS)
                continue;

            char devicePath[256];
            WideCharToMultiByte(CP_UTF8, 0, target.monitorDevicePath, -1, devicePath, sizeof(devicePath), NULL, NULL);
            if (_stricmp(devicePath, monitorDevice.DeviceID) != 0)
                continue;

            *isBuiltinOut = (target.outputTechnology == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL);
            if (target.flags.friendlyNameFromEdid) {
                WideCharToMultiByte(CP_UTF8, 0, target.monitorFriendlyDeviceName, -1,
                                    nameOut, (int)nameOutSize, NULL, NULL);
            }
            break;
        }
    }

    free(paths);
    free(modes);
}

static BOOL CALLBACK monitorEnumProc(HMONITOR hMonitor, HDC hdcMonitor, LPRECT lprcMonitor, LPARAM dwData) {
    (void)hdcMonitor;
    (void)lprcMonitor;
    (void)dwData;

    if (gDisplayCount >= MAX_DISPLAYS)
        return FALSE;

    MONITORINFOEXA monInfo;
    memset(&monInfo, 0, sizeof(monInfo));
    monInfo.cbSize = sizeof(monInfo);
    if (!GetMonitorInfoA(hMonitor, (MONITORINFO *)&monInfo))
        return TRUE;

    DWORD numPhysical = 0;
    if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, &numPhysical) || numPhysical == 0)
        return TRUE;

    PHYSICAL_MONITOR *phys = calloc(numPhysical, sizeof(PHYSICAL_MONITOR));
    if (!phys)
        return TRUE;

    if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, numPhysical, phys)) {
        free(phys);
        return TRUE;
    }

    for (DWORD i = 0; i < numPhysical && gDisplayCount < MAX_DISPLAYS; i++) {
        DisplayInfo *info = &gDisplays[gDisplayCount];
        memset(info, 0, sizeof(*info));
        info->physMon = phys[i];
        info->isBuiltin = FALSE;
        WideCharToMultiByte(CP_UTF8, 0, phys[i].szPhysicalMonitorDescription, -1,
                            info->productName, NAME_BUF_SIZE, NULL, NULL);
        // A single HMONITOR maps to one target; only the first physical
        // monitor behind it (the common case) can be identified this way.
        if (i == 0)
            lookupMonitorIdentity(monInfo.szDevice, info->productName, NAME_BUF_SIZE, &info->isBuiltin);
        gDisplayCount++;
    }

    free(phys);
    return TRUE;
}

static int discoverDisplays(void) {
    gDisplayCount = 0;
    EnumDisplayMonitors(NULL, NULL, monitorEnumProc, 0);
    return gDisplayCount;
}

static void destroyAllMonitors(void) {
    for (int i = 0; i < gDisplayCount; i++)
        DestroyPhysicalMonitor(gDisplays[i].physMon.hPhysicalMonitor);
}

// Picks the display to control: prefers a product-name match (default
// "XENEON"), otherwise the first non-built-in display, otherwise whatever
// display we found at all.
static DisplayInfo *selectDisplay(const char *nameMatch, BOOL verbose) {
    DisplayInfo *preferred = NULL;
    DisplayInfo *firstExternal = NULL;

    for (int i = 0; i < gDisplayCount; i++) {
        if (gDisplays[i].isBuiltin) continue;
        if (!firstExternal) firstExternal = &gDisplays[i];
        if (nameMatch && containsIgnoreCase(gDisplays[i].productName, nameMatch)) {
            preferred = &gDisplays[i];
            break;
        }
    }

    DisplayInfo *chosen = preferred ? preferred : firstExternal;
    if (!chosen && gDisplayCount > 0) {
        if (verbose) fprintf(stderr, "No external display found; falling back to the first display.\n");
        chosen = &gDisplays[0];
    }
    if (chosen && verbose)
        fprintf(stderr, "Using display: %s\n", chosen->productName);
    return chosen;
}

// ---------- Commands ----------

static int cmdList(void) {
    if (gDisplayCount == 0) {
        printf("No displays found.\n");
        return EXIT_SUCCESS;
    }
    for (int i = 0; i < gDisplayCount; i++) {
        printf("[%d] %-24s %s\n", i, gDisplays[i].productName,
               gDisplays[i].isBuiltin ? "(built-in)" : "(external)");
    }
    return EXIT_SUCCESS;
}

static int cmdGet(HANDLE hPhysicalMonitor, const Setting *setting) {
    DWORD current = 0, max = 0;
    MC_VCP_CODE_TYPE codeType;
    if (!GetVCPFeatureAndVCPFeatureReply(hPhysicalMonitor, setting->vcpCode, &codeType, &current, &max)) {
        fprintf(stderr, "DDC read failed for '%s' (error 0x%08lX)\n", setting->name, GetLastError());
        return EXIT_FAILURE;
    }
    printf("%lu (max %lu)\n", current, max);
    return EXIT_SUCCESS;
}

static int cmdSet(HANDLE hPhysicalMonitor, const Setting *setting, const char *rawValue) {
    int value;
    if (_stricmp(rawValue, "on") == 0)       value = 1;
    else if (_stricmp(rawValue, "off") == 0) value = 2;
    else                                     value = atoi(rawValue);

    if (value < 0 || value > 65535) {
        fprintf(stderr, "Value out of range: %s\n", rawValue);
        return EXIT_FAILURE;
    }

    if (!SetVCPFeature(hPhysicalMonitor, setting->vcpCode, (DWORD)value)) {
        fprintf(stderr, "DDC write failed for '%s' (error 0x%08lX)\n", setting->name, GetLastError());
        return EXIT_FAILURE;
    }
    printf("Set %s to %d\n", setting->name, value);
    return EXIT_SUCCESS;
}

// ---------- main ----------

int main(int argc, char *argv[]) {
    BOOL verbose = FALSE;
    int argi = 1;
    if (argi < argc && (strcmp(argv[argi], "-v") == 0 || strcmp(argv[argi], "--verbose") == 0)) {
        verbose = TRUE;
        argi++;
    }

    if (argi >= argc || strcmp(argv[argi], "help") == 0 ||
        strcmp(argv[argi], "-h") == 0 || strcmp(argv[argi], "--help") == 0) {
        printUsage();
        return (argi >= argc) ? EXIT_FAILURE : EXIT_SUCCESS;
    }

    const char *command = argv[argi++];

    if (strcmp(command, "list") != 0 && strcmp(command, "get") != 0 && strcmp(command, "set") != 0) {
        fprintf(stderr, "Unknown command '%s'. Use 'list', 'get', or 'set'.\n", command);
        return EXIT_FAILURE;
    }

    discoverDisplays();

    if (strcmp(command, "list") == 0) {
        int result = cmdList();
        destroyAllMonitors();
        return result;
    }

    if (argi >= argc) {
        destroyAllMonitors();
        fprintf(stderr, "Missing setting name. Run 'xeneonctl help' for usage.\n");
        return EXIT_FAILURE;
    }
    const Setting *setting = settingNamed(argv[argi++]);
    if (!setting) {
        destroyAllMonitors();
        fprintf(stderr, "Unknown setting. Choose one of: brightness, contrast, volume, mute, input.\n");
        return EXIT_FAILURE;
    }

    DisplayInfo *display = selectDisplay(kDefaultDisplayNameMatch, verbose);
    if (!display) {
        destroyAllMonitors();
        die("Could not find a DDC-controllable display. Run 'xeneonctl list' to see what was detected.");
    }

    int result;
    if (strcmp(command, "get") == 0) {
        result = cmdGet(display->physMon.hPhysicalMonitor, setting);
    } else {
        if (argi >= argc) {
            fprintf(stderr, "Missing value. Usage: xeneonctl set %s <value>\n", setting->name);
            result = EXIT_FAILURE;
        } else {
            result = cmdSet(display->physMon.hPhysicalMonitor, setting, argv[argi]);
        }
    }

    destroyAllMonitors();
    return result;
}
