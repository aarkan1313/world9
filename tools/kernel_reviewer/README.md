# Kernel Reviewer

Standalone click-through reviewer for WorldGen9 DEM kernels. It does not depend
on Godot.

Run:

```powershell
.\tools\kernel_reviewer\run_kernel_reviewer.ps1
```

Default input:

```text
factory/catalog/accepted_kernel_catalog.json
```

Default outputs:

```text
factory/reviews/kernel_review_state.json
factory/reviews/user_shortlist_kernel_catalog.json
factory/reviews/user_rejected_kernel_catalog.json
factory/reviews/user_review_queue_kernel_catalog.json
```

The app saves after every click, so it is safe to close and resume later.
