# plosca.ru simplification plan

Planning snapshot: 2026-09-04. Implementation completed and verified below.

## Current state and evidence

- `master` is `47e4743`, matching the recorded remote. The tracked site is a small authored HTML/CSS/JavaScript tree with static articles, previews, and an external-link archive. It has no application framework or elaborate test suite to remove.
- Existing untracked `articles_md/`, `design/`, and `docs/` contain separate work and must remain untouched. They are not redundant merely because the tracked deployment uses `site/`.
- `scripts/deploy.sh` names a release from HEAD and checks tracked cleanliness, but copies the entire working `site/` using rsync. Untracked or ignored site files can therefore enter a supposedly commit-identified release.
- The script uses immutable release directories and atomic `current` promotion. Existing browser scripts provide theme preference, code interaction, and link previews; a caught storage/network failure is not automatically an unnecessary fallback.

## Intended result

Keep the authored static site and make its release contents reproducibly match the selected commit. No compiler migration, component framework, general testing framework, redesign, or forced consolidation with the untracked design work.

## Implementation sequence

1. Preserve all existing untracked work. Capture one full commit ID at deployment start and derive its release ID and source archive from that same revision; do not reread moving HEAD halfway through staging.
2. Stage the committed `site/` tree using Git archive/export, excluding working-tree untracked and ignored files by construction. Keep the existing tracked-cleanliness policy. Compare staged bytes with any existing immutable release; fail on a collision/mismatch rather than overwrite it.
3. Retain atomic promotion and cleanup. Make the release root explicitly selectable for a disposable rehearsal while retaining the production default. Serialize publishers to that root with one local lock so simultaneous installs cannot nest or overwrite the same release directory. Before promotion, record the prior target for rollback; an identical redeploy must not replace the useful previous target with itself. Keep failure cleanup scoped to this invocation's staging and temporary symlink, and never remove an existing release or current target on failure.
4. Review authored assets for demonstrably unreachable code or duplicated declarations only after checking their actual page users. Preserve progressive behavior when storage is unavailable or preview fetch fails. Do not combine this deployment fix with style churn or a content rewrite.
5. Update the short deploy instructions with source identity, repeat-deploy behavior, and exact rollback command. Keep design/history material separate without moving or deleting it.

## Verification and delivery

- Run shell syntax validation and one disposable deployment rehearsal covering initial release, identical redeploy, an injected untracked/ignored site file that must not publish, a conflicting existing release, concurrent invocation, and failure before promotion that leaves the previous current target usable. Use a temporary checkout/root; do not create test files in the real authored site.
- Verify exported source and staged/released file bytes match, not just directory existence or the release name. Preserve authored downloadable files, font/image assets, archive pages, and Caddy routing. No permanent broad test suite is needed for this small script change; retain a focused executable regression check only if it directly exercises these failure contracts without duplicating the deploy logic.
- If HTML/CSS/JavaScript changes, inspect the affected pages/interactions in a browser with narrow/mobile and desktop layouts; include native navigation and relevant storage/network failure behavior. Do not introduce an unrelated screenshot matrix for a deployment-only edit.
- Preserve the existing Analytico tracker URL unless coordinating an actual tracker asset update with the Analytico project. Changing a hash without releasing the matching asset can break collection.
- Review export identity, immutable-directory handling, cleanup, and rollback adversarially; fix findings and repeat until a complete pass has no new or unresolved blockers. Commit only reviewed task files, push to `master`, and verify the remote revision.
- Script/docs-only changes do not require publishing unchanged site content. If site content changes, use the corrected deploy path and prove source/release/public asset identity, representative pages, and retained rollback target. Keep Caddy configuration changes outside scope unless the actual release requires one.

## Planning review

- Pass 1 found that exporting from a second HEAD read could mismatch release identity, that idempotent promotion could erase a useful rollback target, and that concurrent installs need serialization beyond atomic symlink replacement. The plan now captures one revision, preserves the prior distinct release, and uses one root-specific lock. Existing browser recovery behavior and untracked design work are explicitly preserved.
- Pass 2 checked the deploy script, Caddy route/asset behavior, authored tree, tracker URL, and browser failure handling against the revised sequence. No unresolved or new planning blockers were found. This is primarily a release correctness fix; no broad test deletion or website rewrite is justified by the inspected project.

## Implementation and review result

- Publication now exports one captured full Git revision. Untracked and ignored
  site files cannot enter a release. Existing releases are compared without
  dereferencing symlinks and never overwritten; release directory symlinks and
  unusable current/previous links are rejected.
- One release-root lock serializes publishers. A temporary directory owns this
  invocation's staging and promotion links. Atomic current promotion records the
  prior distinct release; identical redeploys retain the useful rollback target.
  An ordinary promotion failure restores prior rollback metadata.
- README documents the production root, disposable-root override, committed
  source identity, and a lock-protected atomic rollback command.
- Reviewed theme storage failures, clipboard interaction, and preview fetch/error
  paths against their page users. These preserve useful progressive behavior;
  no authored asset rewrite or test deletion was justified. All 49 site files,
  including the tracker URL, remain unchanged. Existing untracked design,
  article, and documentation directories were not touched.

Review pass 1 and a real non-root rehearsal exposed directory chmod ordering:
read-only staging directories cannot be renamed across parents by the ordinary
publisher. Permissions are now finalized after installation and before promotion.
Review pass 2 added rejection of a symlink release directory and verified failed
promotion restores `previous`. The focused executable journey passed initial
publish, identical redeploy, untracked/ignored exclusion, dirty-tree rejection,
conflicting bytes, symlink collision, injected current-rename failure, concurrent
publishers, HEAD movement during export, and the documented rollback sequence.
A disposable mutation replacing Git archive with working-tree copying failed
the release-content assertion. A separate rehearsal exported the complete
authored site and compared all 49 file contents successfully. Shell syntax and
final diff checks passed. The final review found no unresolved or new blockers.

Delivery: committed and pushed to `master`; no production publication is needed
for this script/test/documentation change. Caddy, current public content, and
existing rollback releases are preserved. The primary checkout is advanced only
if its original tracked state and unrelated untracked files remain intact.
