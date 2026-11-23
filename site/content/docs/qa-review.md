+++
title = "Card review (QA)"
description = "Approve cards, mark the ones that need changes, and see what changed since you looked."
+++

Card review lets you go through a set card by card and record what you decided. It lives in the editor and keeps its state in [`qa.json`](@/docs/project-layout-and-manifest.md#card-review-qa-json) next to the rest of the project, so a reviewer's work is committed, diffed and shared like any other file. The command line does not read it.

## Reviewing a set

1. Open the set in the editor and pick a card in the card picker. Every card shows a badge: **Unreviewed**, **Approved**, **Needs changes** or **Changed since review**.
2. Look at the card, then use the review controls under the preview:
   - **Approve** records the card as it is now.
   - **Needs changes** flags the card. Write what is wrong in the note field; the note is saved with the mark.
   - **Clear** removes the review.
3. Open the card list and tick **Needs review (n)** to see what is left. It lists unreviewed cards, cards that changed since you approved them, and cards marked **Needs changes**. A set is done when the filter says "No card needs review."

Reviews are saved like any other edit, so they take part in undo and in saving to a linked folder.

## What counts as a change

An approval stores a hash of what the card's render depends on, so it only turns into **Changed since review** when the card could look different:

- **The card's values.** Editing any field of the card changes it. Reordering keys or reformatting the card file does not.
- **The design it uses**, and the components that design includes (also through other components). Editing a component only affects the designs that include it, so cards of other designs keep their approval. Reformatting a design or component file does not count; changing its content does.
- **The card id**, only if the design reads `card.id`. Otherwise the id is just a name.

Images and fonts are not part of the hash. After a change to a design, every card of that design (and only those) needs another look; that is the price of being sure, since the editor cannot tell which cards a changed layer touches.

**Needs changes** stays until you clear it or approve the card again, even if the card has been edited since. Fix the card, look at it, then press **Approve**.

## Renaming and moving cards

A review follows the card, not its name. If you rename a card id, move a card to another set, or rename a card file, the review is found again by matching the card's content, and the mark and note come with it. This only works while the card's values and its design are unchanged; if you rename and edit a card in one step, it counts as a new card. Two cards with identical content share one review once: the first one in the set gets it.

The file is brought up to date the next time you record a review. Until then the old entry just sits in `qa.json`.

## Working in a team

- Commit `qa.json` with the cards. A reviewer's approvals then show up in the diff of the pull request.
- Entries are sorted by card file and card id, so two people reviewing different cards usually merge without conflicts.
- To start over, delete `qa.json` or press **Clear** on a card.

See [Project layout and manifest](@/docs/project-layout-and-manifest.md#card-review-qa-json) for the file format.
