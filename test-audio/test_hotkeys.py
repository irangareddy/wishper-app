#!/usr/bin/env python3
"""
Test hotkeys by simulating key events via CGEvent.
Verifies that Control+Space triggers hands-free mode.
"""
import time
import subprocess
import Quartz

def simulate_key(keycode, flags=0, key_down=True):
    """Simulate a key event via CGEvent."""
    event = Quartz.CGEventCreateKeyboardEvent(None, keycode, key_down)
    if flags:
        Quartz.CGEventSetFlags(event, flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

def test_control_space():
    """Simulate Control+Space (hands-free trigger)."""
    print("Testing Control+Space (hands-free)...")
    print("  Pressing Control+Space...")

    # Key codes
    SPACE = 49
    CONTROL_FLAG = Quartz.kCGEventFlagMaskControl

    # Press Control+Space
    simulate_key(SPACE, flags=CONTROL_FLAG, key_down=True)
    time.sleep(0.05)
    simulate_key(SPACE, flags=CONTROL_FLAG, key_down=False)

    print("  Released. Waiting 3 seconds for recording...")
    time.sleep(3)

    # Now simulate fn press to stop (keycode 63, flagsChanged)
    print("  Simulating fn press to stop hands-free...")
    fn_event = Quartz.CGEventCreate(None)
    Quartz.CGEventSetType(fn_event, Quartz.kCGEventFlagsChanged)
    Quartz.CGEventSetIntegerValueField(fn_event, Quartz.kCGKeyboardEventKeycode, 63)
    Quartz.CGEventSetFlags(fn_event, Quartz.kCGEventFlagMaskSecondaryFn)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, fn_event)
    time.sleep(0.1)

    # Release fn
    fn_up = Quartz.CGEventCreate(None)
    Quartz.CGEventSetType(fn_up, Quartz.kCGEventFlagsChanged)
    Quartz.CGEventSetIntegerValueField(fn_up, Quartz.kCGKeyboardEventKeycode, 63)
    Quartz.CGEventSetFlags(fn_up, 0)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, fn_up)

    print("  Done. Check if Wishper transcribed and pasted.")

if __name__ == "__main__":
    print("=" * 50)
    print("Wishper Hotkey Test")
    print("=" * 50)
    print()
    print("Make sure Wishper is running.")
    print("Starting in 3 seconds...")
    time.sleep(3)

    test_control_space()
    print("\nTest complete.")
