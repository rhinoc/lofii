# Live2D Cubism Native SDK

This repository keeps the Cubism Framework source used by the native renderer.
The Cubism Core header and macOS runtime library are not committed because they
are governed by Live2D's Proprietary Software License.

Install Cubism Core locally from an official Cubism SDK for Native archive:

```bash
scripts/install_cubism_core.sh
```

CI uses the same script. `CUBISM_NATIVE_SDK_URL` can override the default
official SDK URL when needed.
