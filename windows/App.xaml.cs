using System.IO;
using System.Windows;

namespace ThreeD;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Headless mode: render a model to a PNG and exit.
        // Usage: ThreeD.exe --snapshot <model> <output.png> [width height]
        if (e.Args.Length >= 3 && e.Args[0] == "--snapshot")
        {
            int exitCode = 0;
            try
            {
                int width = e.Args.Length >= 5 ? int.Parse(e.Args[3]) : 800;
                int height = e.Args.Length >= 5 ? int.Parse(e.Args[4]) : 600;
                Snapshot.Run(e.Args[1], e.Args[2], width, height);
            }
            catch (Exception ex)
            {
                try { File.WriteAllText(e.Args[2] + ".err.txt", ex.ToString()); } catch { }
                exitCode = 1;
            }
            Shutdown(exitCode);
            return;
        }

        var window = new MainWindow();
        window.Show();

        if (e.Args.Length >= 1 && File.Exists(e.Args[0]))
            window.OpenFileWhenLoaded(e.Args[0]);
    }
}
