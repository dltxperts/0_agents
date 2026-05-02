---
name: dictate
description: Dictation cleanup for mixed Russian/English tech text. Replaces transliterated tech terms with English equivalents, structures the text, and asks whether to execute. Auto-invokes when user pastes dictated Russian text with tech terms.
user-invocable: true
disable-model-invocation: false
---

# Dictation Cleanup

You received dictated text that mixes Russian and English. Clean up transliterated tech terms (ревью->review, коммит->commit, смержить->merge, бранч->branch, фича->feature, etc.), lightly structure the text, and present the cleaned version in a code block.

If it's a command — ask "Выполнять?" If it's a note — ask "Ок?"

## Dictated text

$ARGUMENTS
