+++
title = "Card review (QA)"
description = "Approve cards, mark the ones that need changes, and see what changed since you looked."
+++

Card review lets you go through a set card by card and record what you decided. It lives in the editor and keeps its state in [`qa.json`](@/docs/project-layout-and-manifest.md#card-review-qa-json) next to the rest of the project, so a reviewer's work is committed, diffed and shared like any other file. The command line does not read it.

## Reviewing a set

1. Open the set in the editor, go to the **Card data** tab and pick a card. Every card shows a badge: **Unreviewed**, **Approved**, **Needs changes** or **Changed since review**.
2. Look at the card, then use the review controls under it:
   - **Approve** records the card as it is now. It is disabled while the card has open comments.
   - **Needs changes** flags the card.
   - **Clear** removes the mark (the comments stay).
3. To say what is wrong, write a **comment** (the field at the bottom, key <kbd>C</kbd>). A card can have as many as you like, and a card with an open comment counts as **Needs changes**, shown as "5 open".
4. Open the card list and tick **Needs review (n)** to see what is left: unreviewed cards, cards that changed since you approved them, and cards that need changes. A set is done when the filter says "No card needs review."

Reviews are saved like any other edit, so they take part in undo and in saving to a linked folder.

## Comments and pins

Each comment has a text, an optional pin, and **Resolve** / **Reopen**. Press **Pin** (or <kbd>P</kbd>) on a comment and click the card to put a numbered bubble on the spot it is about; **Move** places it again. Click a bubble to highlight its comment. The bubbles only exist in the editor: they are never part of a render or an export.

Resolve a comment once it is fixed. When all comments are resolved, the card is back to its mark: approve it again if it was marked as needing changes. Pins are positions on the card, so if you move layers later a pin can point at the wrong spot; resolve or delete such a comment.

The **Overview** (button or <kbd>O</kbd>) lists every card of the project that has a mark or a comment, with all its comments. Click a row to go to the card.

## Keys

These work when the focus is not in a text field. <kbd>?</kbd> shows the list in the editor.

| Keys | Does |
| --- | --- |
| <kbd>J</kbd> / <kbd>K</kbd> | Next / previous card |
| <kbd>]</kbd> / <kbd>[</kbd> | Next / previous design |
| <kbd>U</kbd> | Next card that needs review, also in other designs |
| <kbd>A</kbd> | Approve |
| <kbd>N</kbd> | Needs changes |
| <kbd>X</kbd> | Remove the mark |
| <kbd>C</kbd> | Write a comment |
| <kbd>P</kbd> | Pin the selected comment, then click the card |
| <kbd>O</kbd> | Overview |
| <kbd>?</kbd> | The list of keys |
| <kbd>Esc</kbd> | Cancel pinning, close the windows |

A fast pass through a set: <kbd>U</kbd> to the first card, look, <kbd>A</kbd> to approve or <kbd>C</kbd> to comment, <kbd>U</kbd> again.

## Your name

Under **Project settings** you can set **Your name for reviews**: a username is enough, it is optional, and it is kept in this browser only. When set, it is written next to the marks and comments you add, with the date. It is a label in a file that anyone can edit, not a login.

## What counts as a change

An approval stores a hash of what the card's render depends on, so it only turns into **Changed since review** when the card could look different:

- **The card's values.** Editing any field of the card changes it. Reordering keys or reformatting the card file does not.
- **The design it uses**, and the components that design includes (also through other components). Editing a component only affects the designs that include it, so cards of other designs keep their approval. Reformatting a design or component file does not count; changing its content does.
- **The card id**, only if the design reads `card.id`. Otherwise the id is just a name.

Images and fonts are not part of the hash. After a change to a design, every card of that design (and only those) needs another look; that is the price of being sure, since the editor cannot tell which cards a changed layer touches.

**Needs changes** stays until you clear it or approve the card again, even if the card has been edited since, and comments stay with the card whatever changes. Fix the card, resolve the comments, then press **Approve**.

## Renaming and moving cards

A review follows the card, not its name. If you rename a card id, move a card to another set, or rename a card file, the review is found again by matching the card's content, and the mark and comments come with it. This only works while the card's values and its design are unchanged; if you rename and edit a card in one step, it counts as a new card. Two cards with identical content share one review once: the first one in the set gets it.

The file is brought up to date the next time you record a review. Until then the old entry just sits in `qa.json`.

## Working in a team

- Commit `qa.json` with the cards. A reviewer's approvals then show up in the diff of the pull request.
- Entries are sorted by card file and card id, so two people reviewing different cards usually merge without conflicts.
- To start over, delete `qa.json` or press **Clear** on a card.

See [Project layout and manifest](@/docs/project-layout-and-manifest.md#card-review-qa-json) for the file format.
