#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Center Window
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎯
# @raycast.packageName Window Management

# Documentation:
# @raycast.description Resizes the frontmost window to a fixed size and centers it on the display it is on (laptop or ultrawide).
# @raycast.author asaday
# @raycast.authorURL https://raycast.com/asaday

osascript -l JavaScript <<'EOF'
ObjC.import("AppKit");

// Same size in points on every display, so it stays laptop-shaped on the ultrawide
const TARGET_WIDTH = 1500;
const TARGET_HEIGHT = 900;
// Never take more than this fraction of the display's usable area
const MAX_FRACTION = 0.9;

const se = Application("System Events");
const proc = se.processes.whose({ frontmost: true })[0];
const win = proc.windows[0];

const [winX, winY] = win.position();
const [winW, winH] = win.size();
const centerX = winX + winW / 2;
const centerY = winY + winH / 2;

// NSScreen uses bottom-left origin; System Events uses top-left of the primary display
const screens = $.NSScreen.screens;
const primaryHeight = screens.objectAtIndex(0).frame.size.height;

let target = null;
for (let i = 0; i < screens.count; i++) {
  const v = screens.objectAtIndex(i).visibleFrame;
  const area = {
    x: v.origin.x,
    y: primaryHeight - (v.origin.y + v.size.height),
    w: v.size.width,
    h: v.size.height,
  };
  if (!target) target = area;
  if (centerX >= area.x && centerX < area.x + area.w && centerY >= area.y && centerY < area.y + area.h) {
    target = area;
    break;
  }
}

const width = Math.round(Math.min(TARGET_WIDTH, target.w * MAX_FRACTION));
const height = Math.round(Math.min(TARGET_HEIGHT, target.h * MAX_FRACTION));
const x = Math.round(target.x + (target.w - width) / 2);
const y = Math.round(target.y + (target.h - height) / 2);

// Move first so the resize happens on the destination display, then size, then re-position
win.position = [x, y];
win.size = [width, height];
win.position = [x, y];
EOF
