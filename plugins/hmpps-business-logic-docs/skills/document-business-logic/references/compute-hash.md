## Computing the MD5 hash for `docs-change-tracking.yaml`

The `hash` field in each registry entry must be computed exactly as `DocsChangeTrackingTest` computes it — an MD5 digest of the concatenated UTF-8 paths and raw bytes of all resolved source files (sorted by repo-relative path).

### Using Python (fastest)

Copy and adapt this one-liner for your entry's source files:

```bash
python3 -c "
import hashlib
paths = [
    'src/main/kotlin/uk/gov/justice/digital/hmpps/yourservice/service/YourService.kt',
]
d = hashlib.md5()
for p in sorted(paths):
    d.update(p.encode('utf-8'))
    d.update(b'\x00')
    with open(p, 'rb') as f:
        d.update(f.read())
print(d.hexdigest())
"
```

For a `sources` entry that's a **directory**, expand the `paths` list with every `*.kt` file under it (sorted):

```bash
find src/main/kotlin/uk/gov/justice/digital/hmpps/yourservice/service -name "*.kt" -type f | sort
```

Then add each resolved file path to the `paths` list in the one-liner above.

### Using test output (simpler if unsure)

If you're uncertain about the computation:

1. Put in a deliberately wrong hash value (e.g., `hash: 00000000000000000000000000000000`)
2. Run:
   ```bash
   ./gradlew test --tests "*DocsChangeTrackingTest*"
   ```
3. The test failure message will print the correct hash — copy it directly

Both approaches yield identical results; the Python one-liner is just faster if you're registering multiple entries.

### What the test actually does

For reference, `DocsChangeTrackingTest` (in Kotlin) performs this computation:

```kotlin
private fun hashOf(files: List<File>): String {
  val digest = MessageDigest.getInstance("MD5")
  files.forEach { file ->
    digest.update(file.relativeTo(repoRoot).path.toByteArray(Charsets.UTF_8))
    digest.update(0)
    digest.update(file.readBytes())
  }
  return digest.digest().joinToString("") { "%02x".format(it) }
}
```

Where `files` are sorted by their repo-relative path before the digest is computed.
