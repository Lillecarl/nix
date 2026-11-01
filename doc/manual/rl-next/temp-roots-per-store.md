---
synopsis: "Several local stores in one process keep each other's temporary roots"
prs: []
---

When one process opened the same local store twice, the second store deleted the temporary roots of the first.
The garbage collector could then delete a path that the first store was still using.
This affects programs that open several stores through the C API.
Each store now has its own temporary roots file.
