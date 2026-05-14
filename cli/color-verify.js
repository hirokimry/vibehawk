// Throwaway test file for verifying Issue #121 bundled review colored badge.
// This file intentionally contains code smells so vibehawk produces bundled
// inline comments. It will be removed before/after merge.

function verifyBundledColor(input) {
  // Bug 1: assignment in condition (likely intended ===)
  if (input = 1) {
    console.log('matched');
  }

  // Bug 2: unused parameter
  function inner(x, y) {
    return x;
  }

  // Bug 3: magic number without explanation
  const limit = 42;

  // Bug 4: console.log left in production code
  console.log('debug:', input);

  return inner(input, limit);
}

module.exports = { verifyBundledColor };
