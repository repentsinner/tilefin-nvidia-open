#!/bin/bash
# Waybar module: shows dot when notifications are pending

count=$(makoctl list | grep -c '"app-name"' 2>/dev/null || echo 0)

if [ "$count" -gt 0 ]; then
    echo "{\"text\": \"●\", \"tooltip\": \"$count notification(s)\", \"class\": \"has-notifications\"}"
else
    echo "{\"text\": \"\", \"tooltip\": \"No notifications\"}"
fi
