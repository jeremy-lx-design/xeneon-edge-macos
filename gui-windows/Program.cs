// A very small WinForms front end for the `xeneonctl` CLI: three sliders,
// nothing else. All the actual DDC/CI protocol work happens in the CLI
// binary (..\xeneonctl.exe); this just shells out to it.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace XeneonUI;

static class CLI
{
    public static readonly string? BinaryPath = FindBinary();

    private static string? FindBinary()
    {
        string appDir = AppContext.BaseDirectory;
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string[] candidates =
        {
            Path.Combine(appDir, "xeneonctl.exe"),
            // gui-windows/bin/<Config>/<Tfm>/ -> repo root
            Path.Combine(appDir, "..", "..", "..", "..", "xeneonctl.exe"),
            Path.Combine(localAppData, "Programs", "xeneonctl", "xeneonctl.exe"),
        };
        foreach (string candidate in candidates)
        {
            string full = Path.GetFullPath(candidate);
            if (File.Exists(full)) return full;
        }

        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        foreach (string dir in (pathEnv ?? "").Split(Path.PathSeparator))
        {
            if (dir.Length == 0) continue;
            try
            {
                string full = Path.Combine(dir, "xeneonctl.exe");
                if (File.Exists(full)) return full;
            }
            catch (ArgumentException) { /* malformed PATH entry */ }
        }
        return null;
    }

    private static string? Run(params string[] args)
    {
        if (BinaryPath == null) return null;
        var psi = new ProcessStartInfo(BinaryPath)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (string arg in args) psi.ArgumentList.Add(arg);

        try
        {
            using var process = Process.Start(psi);
            if (process == null) return null;
            string output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            return process.ExitCode == 0 ? output : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public static int? Get(string setting)
    {
        string[]? parts = Run("get", setting)?.Trim().Split(' ');
        return parts is { Length: > 0 } && int.TryParse(parts[0], out int value) ? value : null;
    }

    public static void Set(string setting, int value) => Run("set", setting, value.ToString());
}

public class MainForm : Form
{
    private readonly TableLayoutPanel layout = new()
    {
        Dock = DockStyle.Fill,
        ColumnCount = 2,
    };

    public MainForm()
    {
        Text = "Xeneon Edge";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(300, 250);
        Padding = new Padding(16);
        Font = SystemFonts.MessageBoxFont ?? SystemFonts.DefaultFont;

        // Sliders take all the width; the value readout gets just what it needs.
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        Controls.Add(layout);

        ShowMessage("Reading display…", SystemColors.ControlText);
        Load += async (_, _) => await LoadValuesAsync();
    }

    // TableLayoutPanel keeps its row count across a Controls.Clear(), which
    // would leave the next control stranded below the rows just removed.
    private void ResetLayout()
    {
        layout.Controls.Clear();
        layout.RowCount = 0;
    }

    private void ShowMessage(string message, Color color)
    {
        ResetLayout();
        var label = new Label { Text = message, AutoSize = true, ForeColor = color };
        layout.Controls.Add(label, 0, 0);
        layout.SetColumnSpan(label, 2);
        layout.RowCount = 1;
    }

    private async Task LoadValuesAsync()
    {
        if (CLI.BinaryPath == null)
        {
            ShowMessage("xeneonctl.exe not found.\nRun 'make' in the project root first.", Color.Firebrick);
            return;
        }

        var values = await Task.Run<(int Brightness, int Contrast, int Volume)?>(() =>
        {
            int? b = CLI.Get("brightness");
            int? c = CLI.Get("contrast");
            int? v = CLI.Get("volume");
            return (b is null || c is null || v is null) ? null : (b.Value, c.Value, v.Value);
        });

        if (values is null)
        {
            ShowMessage("Could not read display settings.\nIs the XENEON EDGE connected?", Color.Firebrick);
            return;
        }

        ResetLayout();
        AddSlider("Brightness", "brightness", values.Value.Brightness);
        AddSlider("Contrast", "contrast", values.Value.Contrast);
        AddSlider("Volume", "volume", values.Value.Volume);
    }

    private void AddSlider(string title, string setting, int initialValue)
    {
        int row = layout.RowCount;

        var titleLabel = new Label { Text = title, AutoSize = true, Anchor = AnchorStyles.Left };
        var valueLabel = new Label
        {
            Text = initialValue.ToString(),
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Anchor = AnchorStyles.Right,
        };
        var slider = new TrackBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = Math.Clamp(initialValue, 0, 100),
            TickStyle = TickStyle.None,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 0, 0, 8),
        };

        // Update the readout live while dragging, but only talk to the panel
        // once the user lets go - DDC/CI writes are slow.
        slider.ValueChanged += (_, _) => valueLabel.Text = slider.Value.ToString();
        slider.MouseUp += (_, _) => Apply();
        slider.KeyUp += (_, _) => Apply();

        void Apply()
        {
            int newValue = slider.Value;
            Task.Run(() => CLI.Set(setting, newValue));
        }

        layout.Controls.Add(titleLabel, 0, row);
        layout.Controls.Add(valueLabel, 1, row);
        layout.Controls.Add(slider, 0, row + 1);
        layout.SetColumnSpan(slider, 2);
        layout.RowCount = row + 2;
    }
}

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
