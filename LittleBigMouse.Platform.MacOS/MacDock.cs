#nullable enable
using System;
using System.Runtime.InteropServices;

namespace LittleBigMouse.Platform.MacOS;

/// <summary>
/// Shows or hides the app's Dock icon at run time through
/// <c>-[NSApplication setActivationPolicy:]</c>: "regular" is an ordinary app with a Dock
/// icon and a menu bar, "accessory" lives in the menu bar only (no Dock icon, no app menu),
/// like most menu-bar utilities.
/// </summary>
public static class MacDock
{
    const string ObjC = "/usr/lib/libobjc.A.dylib";

    // NSApplicationActivationPolicy
    const long PolicyRegular = 0;
    const long PolicyAccessory = 1;

    [DllImport(ObjC)] static extern IntPtr objc_getClass(string name);
    [DllImport(ObjC)] static extern IntPtr sel_registerName(string name);

    [DllImport(ObjC, EntryPoint = "objc_msgSend")]
    static extern IntPtr Send(IntPtr receiver, IntPtr selector);

    [DllImport(ObjC, EntryPoint = "objc_msgSend")]
    static extern byte SendLong(IntPtr receiver, IntPtr selector, long arg);

    [DllImport(ObjC, EntryPoint = "objc_msgSend")]
    static extern void SendBool(IntPtr receiver, IntPtr selector, byte arg);

    static IntPtr SharedApplication()
        => Send(objc_getClass("NSApplication"), sel_registerName("sharedApplication"));

    /// <summary>
    /// Show (<paramref name="visible"/> = true) or hide the Dock icon. Showing it also brings
    /// the app to the front, so a window opened from the menu-bar icon isn't left behind
    /// whatever app was active. Must run on the main (UI) thread. No-op off macOS.
    /// </summary>
    public static void SetVisible(bool visible)
    {
        if (!OperatingSystem.IsMacOS()) return;
        try
        {
            var app = SharedApplication();
            if (app == IntPtr.Zero) return;

            SendLong(app, sel_registerName("setActivationPolicy:"), visible ? PolicyRegular : PolicyAccessory);
            if (visible)
                SendBool(app, sel_registerName("activateIgnoringOtherApps:"), 1);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[macOS] could not change the Dock icon: {ex.Message}");
        }
    }
}
