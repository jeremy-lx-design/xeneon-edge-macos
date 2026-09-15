//
// xeneonctl - a tiny command-line tool for controlling screen settings
// (brightness, contrast, volume, mute, input) on a CORSAIR XENEON EDGE,
// or any other DDC/CI-capable external display connected via USB-C /
// DisplayPort Alt Mode on an Apple Silicon Mac.
//
// It talks DDC/CI directly to the panel using Apple's private
// IOAVService API - the same mechanism used by tools such as m1ddc,
// AppleSiliconDDC and MonitorControl. No drivers, daemons or third-party
// libraries required; just the Xcode Command Line Tools.
//
@import Foundation;
@import IOKit;
@import CoreGraphics;
@import Darwin;

#pragma mark - Private CoreDisplay API

// IOAVServiceRef is an opaque private CoreDisplay type; only the pointer matters here.
typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);
extern boolean_t CGDisplayIsBuiltin(CGDirectDisplayID display);

#pragma mark - DDC/CI (VESA MCCS) constants

#define DDC_I2C_CHIP_ADDRESS  0x37   // Standard DDC/CI I2C slave address for all displays.
#define DDC_HOST_ADDRESS      0x51   // Conventional "host" sub-address used in the checksum/offset.
#define DDC_SETTLE_US         10000  // Panels need a short gap between transactions.
#define DDC_WRITE_REPEATS     2      // Some panels drop the first write; repeating is cheap and reliable.

typedef struct {
    const char *name;
    UInt8 vcpCode;
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

#pragma mark - Helpers

static void die(NSString *message) {
    fputs([message UTF8String], stderr);
    fputs("\n", stderr);
    exit(EXIT_FAILURE);
}

static const Setting *settingNamed(const char *name) {
    for (size_t i = 0; i < kSettingsCount; i++) {
        if (strcasecmp(name, kSettings[i].name) == 0) {
            return &kSettings[i];
        }
    }
    return NULL;
}

static void printUsage(void) {
    printf(
        "xeneonctl - control screen settings on the CORSAIR XENEON EDGE (or any\n"
        "DDC/CI display) over USB-C on Apple Silicon.\n"
        "\n"
        "Usage:\n"
        "  xeneonctl list                    List DDC-controllable external displays\n"
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

#pragma mark - Display discovery

#define MAX_DISPLAYS    8
#define NAME_BUF_SIZE   256

typedef struct {
    CGDirectDisplayID displayID;
    io_service_t adapter; // Caller must IOObjectRelease() when done.
    char productName[NAME_BUF_SIZE];
    BOOL isBuiltin;
} DisplayInfo;

// Enumerates online displays, resolving each one's IORegistry framebuffer
// service (needed later to find its DCPAVServiceProxy) and product name.
static int discoverDisplays(DisplayInfo *out, int maxCount) {
    @autoreleasepool {
        CGDirectDisplayID ids[MAX_DISPLAYS];
        uint32_t count = 0;
        CGGetOnlineDisplayList(MAX_DISPLAYS, ids, &count);

        int n = 0;
        for (uint32_t i = 0; i < count && n < maxCount; i++) {
            DisplayInfo *info = &out[n];
            memset(info, 0, sizeof(*info));
            info->displayID = ids[i];
            info->isBuiltin = CGDisplayIsBuiltin(ids[i]);
            info->adapter = MACH_PORT_NULL;
            strlcpy(info->productName, "Unknown display", NAME_BUF_SIZE);

            CFDictionaryRef infoDictRef = CoreDisplay_DisplayCreateInfoDictionary(ids[i]);
            if (infoDictRef) {
                NSDictionary *infoDict = (__bridge_transfer NSDictionary *)infoDictRef;
                NSString *location = infoDict[@"IODisplayLocation"];
                if (location) {
                    io_service_t adapter = IORegistryEntryCopyFromPath(kIOMainPortDefault, (__bridge CFStringRef)location);
                    if (adapter != MACH_PORT_NULL) {
                        info->adapter = adapter;
                        CFTypeRef attrsRef = IORegistryEntrySearchCFProperty(adapter, kIOServicePlane, CFSTR("DisplayAttributes"), kCFAllocatorDefault, kIORegistryIterateRecursively);
                        if (attrsRef) {
                            NSDictionary *displayAttrs = (__bridge_transfer NSDictionary *)attrsRef;
                            NSString *productName = displayAttrs[@"ProductAttributes"][@"ProductName"];
                            if (productName) {
                                strlcpy(info->productName, [productName UTF8String], NAME_BUF_SIZE);
                            }
                        }
                    }
                }
            }
            n++;
        }
        return n;
    }
}

// Walks the IORegistry to find the DCPAVServiceProxy that belongs to the
// given framebuffer adapter, and wraps it as an IOAVService we can send
// DDC/CI I2C transactions to.
static IOAVServiceRef avServiceForAdapter(io_service_t adapter) {
    uint64_t targetFramebufferID;
    if (IORegistryEntryGetRegistryEntryID(adapter, &targetFramebufferID) != KERN_SUCCESS) {
        return NULL;
    }

    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    io_iterator_t iter;
    if (IORegistryEntryCreateIterator(root, kIOServicePlane, kIORegistryIterateRecursively, &iter) != KERN_SUCCESS) {
        return NULL;
    }

    Boolean framebufferMatches = false;
    IOAVServiceRef found = NULL;
    io_service_t service;
    while ((service = IOIteratorNext(iter)) != MACH_PORT_NULL) {
        if (IOObjectConformsTo(service, "IOMobileFramebuffer")) {
            uint64_t framebufferID;
            framebufferMatches = (IORegistryEntryGetRegistryEntryID(service, &framebufferID) == KERN_SUCCESS)
                && framebufferID == targetFramebufferID;
            IOObjectRelease(service);
            continue;
        }

        io_name_t name;
        IORegistryEntryGetName(service, name);
        if (!framebufferMatches || strcmp(name, "DCPAVServiceProxy") != 0) {
            IOObjectRelease(service);
            continue;
        }

        IOAVServiceRef avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
        IOObjectRelease(service);
        if (avService) {
            found = avService;
            break;
        }
    }
    IOObjectRelease(iter);
    return found;
}

// Picks the display to control: prefers a product-name match (default
// "XENEON"), otherwise the first non-built-in display, otherwise falls
// back to whatever IOAVServiceCreate() considers the default AV service.
static IOAVServiceRef selectDisplayAVService(const char *nameMatch, BOOL verbose) {
    DisplayInfo displays[MAX_DISPLAYS];
    int count = discoverDisplays(displays, MAX_DISPLAYS);

    DisplayInfo *preferred = NULL;
    DisplayInfo *firstExternal = NULL;
    for (int i = 0; i < count; i++) {
        if (displays[i].isBuiltin || displays[i].adapter == MACH_PORT_NULL) continue;
        if (!firstExternal) firstExternal = &displays[i];
        if (nameMatch && strcasestr(displays[i].productName, nameMatch)) {
            preferred = &displays[i];
            break;
        }
    }
    DisplayInfo *chosen = preferred ? preferred : firstExternal;

    IOAVServiceRef service = NULL;
    if (chosen) {
        if (verbose) fprintf(stderr, "Using display: %s\n", chosen->productName);
        service = avServiceForAdapter(chosen->adapter);
        if (!service && verbose) {
            fprintf(stderr, "Could not resolve an AVService for that display; falling back to default.\n");
        }
    } else if (verbose) {
        fprintf(stderr, "No external display found; falling back to IOAVServiceCreate() default.\n");
    }

    for (int i = 0; i < count; i++) {
        if (displays[i].adapter != MACH_PORT_NULL) IOObjectRelease(displays[i].adapter);
    }

    return service ?: IOAVServiceCreate(kCFAllocatorDefault);
}

#pragma mark - DDC/CI transport

// "Get VCP Feature" request/reply, and "Set VCP Feature" request, per the
// VESA Monitor Control Command Set (MCCS) spec, tunnelled over I2C via
// IOAVService instead of a physical DDC/CI bus.

static IOReturn ddcGet(IOAVServiceRef service, UInt8 vcpCode, UInt16 *currentOut, UInt16 *maxOut) {
    UInt8 request[4] = {0x82, 0x01, vcpCode, 0};
    request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2];

    IOReturn err = kIOReturnSuccess;
    for (int i = 0; i < DDC_WRITE_REPEATS; i++) {
        usleep(DDC_SETTLE_US);
        err = IOAVServiceWriteI2C(service, DDC_I2C_CHIP_ADDRESS, DDC_HOST_ADDRESS, request, sizeof(request));
        if (err) return err;
    }

    usleep(DDC_SETTLE_US);
    UInt8 reply[16] = {0};
    err = IOAVServiceReadI2C(service, DDC_I2C_CHIP_ADDRESS, DDC_HOST_ADDRESS, reply, 11);
    if (err) return err;

    *maxOut = (UInt16)((reply[6] << 8) | reply[7]);
    *currentOut = (UInt16)((reply[8] << 8) | reply[9]);
    return kIOReturnSuccess;
}

static IOReturn ddcSet(IOAVServiceRef service, UInt8 vcpCode, UInt16 value) {
    UInt8 request[6] = {0x84, 0x03, vcpCode, (UInt8)(value >> 8), (UInt8)(value & 0xFF), 0};
    request[5] = 0x6E ^ DDC_HOST_ADDRESS ^ request[0] ^ request[1] ^ request[2] ^ request[3] ^ request[4];

    IOReturn err = kIOReturnSuccess;
    for (int i = 0; i < DDC_WRITE_REPEATS; i++) {
        usleep(DDC_SETTLE_US);
        err = IOAVServiceWriteI2C(service, DDC_I2C_CHIP_ADDRESS, DDC_HOST_ADDRESS, request, sizeof(request));
        if (err) return err;
    }
    return kIOReturnSuccess;
}

#pragma mark - Commands

static int cmdList(void) {
    DisplayInfo displays[MAX_DISPLAYS];
    int count = discoverDisplays(displays, MAX_DISPLAYS);

    if (count == 0) {
        printf("No displays found.\n");
        return EXIT_SUCCESS;
    }

    for (int i = 0; i < count; i++) {
        printf("[%d] %-24s %s\n", i, displays[i].productName, displays[i].isBuiltin ? "(built-in)" : "(external)");
        if (displays[i].adapter != MACH_PORT_NULL) IOObjectRelease(displays[i].adapter);
    }
    return EXIT_SUCCESS;
}

static int cmdGet(IOAVServiceRef service, const Setting *setting) {
    UInt16 current = 0, max = 0;
    IOReturn err = ddcGet(service, setting->vcpCode, &current, &max);
    if (err) {
        die([NSString stringWithFormat:@"DDC read failed for '%s': %s", setting->name, mach_error_string(err)]);
    }
    printf("%d (max %d)\n", current, max);
    return EXIT_SUCCESS;
}

static int cmdSet(IOAVServiceRef service, const Setting *setting, const char *rawValue) {
    int value;
    if (strcasecmp(rawValue, "on") == 0) value = 1;
    else if (strcasecmp(rawValue, "off") == 0) value = 2;
    else value = atoi(rawValue);

    if (value < 0 || value > 65535) {
        die([NSString stringWithFormat:@"Value out of range: %s", rawValue]);
    }

    IOReturn err = ddcSet(service, setting->vcpCode, (UInt16)value);
    if (err) {
        die([NSString stringWithFormat:@"DDC write failed for '%s': %s", setting->name, mach_error_string(err)]);
    }
    printf("Set %s to %d\n", setting->name, value);
    return EXIT_SUCCESS;
}

#pragma mark - main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL verbose = NO;
        int argi = 1;
        if (argi < argc && (strcmp(argv[argi], "-v") == 0 || strcmp(argv[argi], "--verbose") == 0)) {
            verbose = YES;
            argi++;
        }

        if (argi >= argc || strcmp(argv[argi], "help") == 0 || strcmp(argv[argi], "-h") == 0 || strcmp(argv[argi], "--help") == 0) {
            printUsage();
            return (argi >= argc) ? EXIT_FAILURE : EXIT_SUCCESS;
        }

        const char *command = argv[argi++];

        if (strcmp(command, "list") == 0) {
            return cmdList();
        }

        if (strcmp(command, "get") != 0 && strcmp(command, "set") != 0) {
            fprintf(stderr, "Unknown command '%s'. Use 'list', 'get', or 'set'.\n", command);
            return EXIT_FAILURE;
        }

        if (argi >= argc) {
            fprintf(stderr, "Missing setting name. Run 'xeneonctl help' for usage.\n");
            return EXIT_FAILURE;
        }
        const Setting *setting = settingNamed(argv[argi++]);
        if (!setting) {
            fprintf(stderr, "Unknown setting. Choose one of: brightness, contrast, volume, mute, input.\n");
            return EXIT_FAILURE;
        }

        IOAVServiceRef service = selectDisplayAVService(kDefaultDisplayNameMatch, verbose);
        if (!service) {
            die(@"Could not find a DDC-controllable display. Run 'xeneonctl list' to see what was detected.");
        }

        int result;
        if (strcmp(command, "get") == 0) {
            result = cmdGet(service, setting);
        } else {
            if (argi >= argc) {
                fprintf(stderr, "Missing value. Usage: xeneonctl set %s <value>\n", setting->name);
                result = EXIT_FAILURE;
            } else {
                result = cmdSet(service, setting, argv[argi]);
            }
        }

        CFRelease(service);
        return result;
    }
}
