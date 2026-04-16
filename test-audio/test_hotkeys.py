#!/usr/bin/env python3
"""
Test hotkeys by simulating key events via CGEvent.
Simulates Control+Space to start hands-free, waits 60s, then fn to stop.
"""
import time
import Quartz

def simulate_key(keycode, flags=0, key_down=True):
    event = Quartz.CGEventCreateKeyboardEvent(None, keycode, key_down)
    if flags:
        Quartz.CGEventSetFlags(event, flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

def simulate_fn(pressed):
    event = Quartz.CGEventCreate(None)
    Quartz.CGEventSetType(event, Quartz.kCGEventFlagsChanged)
    Quartz.CGEventSetIntegerValueField(event, Quartz.kCGKeyboardEventKeycode, 63)
    Quartz.CGEventSetFlags(event, Quartz.kCGEventFlagMaskSecondaryFn if pressed else 0)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

print("Wishper Hands-Free Test (60 seconds)")
print("Starting in 3 seconds...")
time.sleep(3)

# Start hands-free with Control+Space
print("▶ Pressing Control+Space → hands-free START")
simulate_key(49, flags=Quartz.kCGEventFlagMaskControl, key_down=True)
time.sleep(0.05)
simulate_key(49, flags=Quartz.kCGEventFlagMaskControl, key_down=False)

print("🎤 Recording for 60 seconds... speak now!")
for i in range(60, 0, -10):
    print(f"  {i}s remaining...")
    time.sleep(10)

# Stop with fn
print("⏹ Pressing fn → hands-free STOP")
simulate_fn(True)
time.sleep(0.1)
simulate_fn(False)

print("✓ Done. Check Wishper for transcription.")
