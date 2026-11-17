using System;
using Avalonia;
using Avalonia.Controls;

namespace LittleBigMouse.Ui.Avalonia.Main;

public partial class PluginsControlsView : UserControl
{
    /// <summary>
    /// Room for the macOS window buttons (close / minimize / zoom). The window draws its own
    /// title bar (ExtendClientAreaToDecorationsHint), so on macOS the system places those three
    /// buttons over the top-left of this toolbar; the toolbar starts after them instead.
    /// </summary>
    const double MacWindowButtonsWidth = 72;

    public PluginsControlsView()
    {
        InitializeComponent();

        // On the inner panel, not the Border: the Border's padding comes from the Toolbar style,
        // which a local value would replace.
        if (OperatingSystem.IsMacOS() && Content is Border { Child: Control buttons })
            buttons.Margin = new Thickness(MacWindowButtonsWidth, 0, 0, 0);
    }
}
