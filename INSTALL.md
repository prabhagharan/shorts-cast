# Installing ShortsCast

ShortsCast is a free, open build that isn't distributed through the App Store, so
macOS shows a one-time warning the first time you open it. These steps clear it.
Works on macOS 12 or later.

## Install

1. Download `ShortsCast-<version>-macOS.zip` from the release below and double-click
   it to unzip. You'll get **ShortsCast**.
2. Drag **ShortsCast** into your **Applications** folder.
3. Double-click **ShortsCast**. macOS says it "cannot be opened because Apple cannot
   check it for malicious software." Click **Done**.
4. Open  **System Settings → Privacy & Security**. Scroll down to the **Security**
   section — you'll see *"ShortsCast was blocked to protect your Mac."* Click
   **Open Anyway**, then confirm with your password or Touch ID.
   (On macOS 12 Monterey / 13 Ventura the path is **System Preferences → Security &
   Privacy → General → Open Anyway** instead.)
5. ShortsCast opens. You only need to do steps 3–4 once.

## Grant permissions (first launch)

For screen capture and the click-driven auto-zoom to work, ShortsCast needs three
permissions. When you first record, macOS will prompt for them — or grant them up
front in **System Settings → Privacy & Security**:

- **Screen Recording**
- **Accessibility**
- **Input Monitoring**

After granting them, **quit and reopen** ShortsCast (macOS applies Accessibility and
Input Monitoring only on the next launch).

## Faster path (if you're comfortable with Terminal)

Instead of steps 3–4 you can clear the download flag directly:

    xattr -dr com.apple.quarantine /Applications/ShortsCast.app

Then open the app normally.
