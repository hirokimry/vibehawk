# Test Review Pipeline Trigger

This document intentionally violates markdown.md and document-writing.md to verify reviewers flag documentation issues. Do not merge.

## Code Examples

Without language specifier (violates markdown.md):

```
echo "hello world"
sed -i 's/foo/bar/' file
```

Another fenced block without lang:

```
SELECT * FROM users WHERE id = ${userId};
```

## Broken Links

See [our docs](https://example.com/this-page-does-not-exist-12345) and [internal](../nonexistent/path.md) and [README](./README-typo.md).

## Inconsistent Terminology

We use "user" and "users" and "User" and "USERS" interchangeably throughout this document. The vibehawk-review and the Vibehawk Review and VIBEHAWK REVIEW all refer to the same thing.

## TODO

- TODO: fix this section
- FIXME: rewrite the explanation
- XXX: this is wrong but kept anyway
- HACK: temporary workaround for the issue described in the never-filed bug

## Outdated Content

The system requires Node.js 10.x (note: actual minimum is 20.x). Run `npm install` followed by `npm run build && npm run start:legacy` (note: `start:legacy` was removed in 2023).

## Very long line that violates the document-writing.md 50 character rule and goes on and on without any line break causing the reader's eye to scroll horizontally instead of vertically which destroys scanability and makes the whole point of writing in markdown pointless because the layout no longer guides the reader through the structure of the argument.

## Misleading Code Snippet

```python
# This function safely loads a YAML file
def load_config(path):
    import yaml
    return yaml.load(open(path).read())
```

The comment claims "safely" but uses `yaml.load` (unsafe — allows arbitrary code execution via `!!python/object/apply`). Comments inconsistent with behavior violate comments.md.

## Hardcoded Credentials in Documentation

Example connection string for testing: `postgres://admin:hunter2@prod-db.example.com:5432/users` — these are the actual production credentials. (This sentence alone should trigger several reviewers.)

## Missing Heading Hierarchy

#### Skipped levels above this h4
###### Skipped levels above this h6

## Duplicate Section Title

## Duplicate Section Title

(intentional — h2 repeated twice)

## Empty Code Block

```

```

## Unbalanced Emphasis

**This is bold but not closed and continues into the next paragraph

And the next paragraph still has the unclosed bold.
