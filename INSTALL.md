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

## Agent (MCP) setup

ShortsCast ships an MCP server, `ShortsCastMCP.app`, so Claude Desktop or Claude
Code can record for you — start a recording, do a task in Chrome, stop, tune the
camera, and export a finished short, all through tool calls. It must run as the
signed app bundle so macOS grants it screen capture.

1. Build/sign the bundle from source: `./Scripts/make-app.sh` → produces
   `.build/ShortsCastMCP.app` (release zips include it at the zip root). Move it
   somewhere stable, e.g. `~/Applications/ShortsCast/ShortsCastMCP.app`.
2. Grant it **Screen Recording**, **Accessibility**, and **Input Monitoring**
   (System Settings → Privacy & Security → add `ShortsCastMCP.app` to each list).
   Launch it once first so it registers: `ShortsCastMCP.app/Contents/MacOS/shortscast-mcp </dev/null`.
3. Register the *inner* executable with your client (not the `.app` — the inner
   Mach-O, so it inherits the bundle's screen-recording grant):

   **Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "shortscast": {
         "command": "/Users/<you>/Applications/ShortsCast/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp"
       }
     }
   }
   ```

   **Claude Code**:
   ```
   claude mcp add shortscast /Users/<you>/Applications/ShortsCast/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp
   ```

4. Restart the client. Ask the agent to "start a recording of Google Chrome", do
   your task, then "stop and export". Files land in `~/Movies/ShortsCast/`.
