#!/bin/bash

sed -Ei "s|(checkpoint = yield maybe_future\(cm\.create_checkpoint\(path\)\))|\1\n        if not checkpoint:\n            return|" /opt/conda/lib/python3.8/site-packages/notebook/services/contents/handlers.py