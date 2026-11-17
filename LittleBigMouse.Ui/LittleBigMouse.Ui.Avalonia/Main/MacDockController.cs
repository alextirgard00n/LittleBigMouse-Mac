using System;
using System.Reactive.Disposables;
using Avalonia.Threading;
using LittleBigMouse.DisplayLayout.Monitors;
using LittleBigMouse.Platform.MacOS;
using ReactiveUI;

namespace LittleBigMouse.Ui.Avalonia.Main;

/// <summary>
/// macOS "Hide from Dock": with the option on, the app has no Dock icon while its window is
/// closed (it lives in the menu bar), and gets one back for as long as the window is open,
/// so it can be switched to with the Dock and Cmd+Tab like any other window. With the option
/// off the Dock icon is always there. Does nothing on other platforms.
/// </summary>
public sealed class MacDockController : IDisposable
{
    readonly CompositeDisposable _subscriptions = [];
    readonly ILayoutOptions _options;
    bool _windowOpen;

    public MacDockController(MainWindowManager windows, ILayoutOptions options)
    {
        _options = options;
        if (!OperatingSystem.IsMacOS()) return;

        void OnWindowOpenChanged(bool open)
        {
            _windowOpen = open;
            Apply();
        }

        windows.WindowOpenChanged += OnWindowOpenChanged;
        Disposable.Create(() => windows.WindowOpenChanged -= OnWindowOpenChanged).DisposeWith(_subscriptions);

        // Also applies the current value once at startup (WhenAnyValue emits immediately):
        // starting minimized with the option on means starting without a Dock icon.
        options.WhenAnyValue(o => o.HideFromDock)
            .Subscribe(_ => Apply())
            .DisposeWith(_subscriptions);
    }

    public void Dispose() => _subscriptions.Dispose();

    void Apply()
    {
        var visible = _windowOpen || !_options.HideFromDock;
        // NSApplication must be driven from the main thread.
        if (Dispatcher.UIThread.CheckAccess()) MacDock.SetVisible(visible);
        else Dispatcher.UIThread.Post(() => MacDock.SetVisible(visible));
    }
}
