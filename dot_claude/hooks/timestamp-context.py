#!/usr/bin/env python3
"""UserPromptSubmit hook: stamp each message with the local wall-clock time.

Claude Code adds this hook's stdout to the model context, so the time a message
was sent stays recoverable from the transcript and elapsed time between messages
can be reasoned about without a `date` call. The hook needs no input, so the
JSON on stdin is ignored and there is nothing to parse.
"""

import datetime
import json
import sys

# astimezone() with no argument adopts the system local zone, so %Z prints the
# local abbreviation (e.g. CEST) rather than UTC.
now = datetime.datetime.now().astimezone()
stamp = now.strftime("%Y-%m-%d %H:%M:%S %Z")

json.dump(
    {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": f"Message sent at local time {stamp}.",
        }
    },
    sys.stdout,
)
