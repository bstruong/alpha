PM ticket: Notes need optional tags end-to-end.

Ship a vertical slice so a user can:
1. Set a tag when creating a note.
2. See that tag on the note in the Turbo Frame list after create (turbo stream prepend).
3. Filter the notes frame by tag via a Stimulus-powered `#tag-query` input on the search form.

Persist `notes.tag` (non-null string, default empty) with a migration. Keep title search working. Leave `bin/rails test` green.
