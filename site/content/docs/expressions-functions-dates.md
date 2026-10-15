+++
title = "Expressions: Dates and Times"
description = "Show, split and shift dates and times, with the render's instant and a UTC offset."
+++

Expressions have no clock. The render receives one instant from whoever starts it, so the same project always gives the same output. Dates and times are **text** in ISO form, so a text param, a card value or a render value can be used directly.

## Accepted text

| Kind | Form | Example |
| --- | --- | --- |
| date | `YYYY-MM-DD` | `2026-10-08` |
| time | `HH:MM` or `HH:MM:SS` | `14:05`, `14:05:09` |
| date-time | `YYYY-MM-DDTHH:MM` or `YYYY-MM-DDTHH:MM:SS`, optionally followed by `Z` | `2026-10-08T14:05:09Z` |

Years are 1 to 9999, the date must exist in the calendar, hours are 0 to 23, and minutes and seconds are 0 to 59. Anything else is error 3105, at render time.

`Z` marks a UTC time. The functions on this page never convert between time zones: they keep the time as it is written, and only do the arithmetic or formatting asked for.

## Render values

These are read from the render, not computed by a function:

| Name | Type | Value |
| --- | --- | --- |
| `render.now` | text | The instant the render starts, in UTC, as `YYYY-MM-DDTHH:MM:SSZ`. Given with `--now` on the command line |
| `render.date` | text | The date `YYYY-MM-DD` in the project's time zone (see below) |
| `render.time` | text | The time `HH:MM:SS` in the project's time zone |

`render.date` and `render.time` are the local date and time: the UTC instant from `render.now` with the [`utc_offset`](@/docs/project-layout-and-manifest.md#time-zone) added. `render.now` itself is always UTC. With `--date` alone on the command line, the time is `00:00:00` and no offset applies (see [Command Line](@/docs/command-line.md)).

## Time zone

A project can set its time zone as a **fixed offset from UTC**, in hours, in `utc_offset` in `yoshida.json`:

```json
{
  "format": 1,
  "utc_offset": 2
}
```

- The value is a number of hours from -14 to 14, and it may be fractional: `5.5` is 5 hours 30 minutes. The default is `0`.
- It applies to `render.date` and `render.time` only. `render.now` stays UTC.
- It is a fixed offset. It does **not** follow daylight saving time, and named zones such as `Europe/Berlin` are not supported. A project for a zone with summer time sets `2` in summer and `1` in winter. See [Known gaps](@/docs/known-gaps.md#dates-and-times).
- `yoshida render --utc-offset HOURS` changes it for one run.

## Formatting

### `date_fmt(value, pattern)`

`(text, text) -> text`. Writes a date, a time or a date-time with a pattern of tokens. Other characters are copied as they are.

- `date_fmt('2026-10-08', 'D MMMM YYYY')` is `8 October 2026`.
- `date_fmt('2026-10-08', 'dddd D MMM')` is `Thursday 8 Oct`.
- `date_fmt(render.time, 'HH:mm')` is the time without seconds.
- A text that is not a date, time or date-time is error 3105. A date token (such as `YYYY`) applied to a time-only text is also error 3105.
- A time token (such as `HH`) on a date-only value gives `00` for hours and minutes, so `date_fmt('2026-10-08', 'HH:mm')` is `00:00`.

Tokens (the pattern is shown with 8 October 2026, 14:05:09):

| Token | Output | Example |
| --- | --- | --- |
| `YYYY` | year, four digits | `2026` |
| `YY` | last two digits of the year | `26` |
| `MMMM` | month name | `October` |
| `MMM` | short month name | `Oct` |
| `MM` | month, two digits | `10` |
| `M` | month | `10` (`1` in January) |
| `DD` | day of the month, two digits | `08` |
| `D` | day of the month | `8` |
| `dddd` | weekday name | `Thursday` |
| `ddd` | short weekday name | `Thu` |
| `HH` | hour, 00 to 23 | `14` |
| `H` | hour, 0 to 23 | `14` (`9` for 09:00) |
| `mm` | minute, two digits | `05` |
| `ss` | second, two digits | `09` |

Notes on the tokens:

- The longest token wins, so `MMMM` is tried before `MMM` and `MM`.
- Tokens are case-sensitive: `MM` is the month and `mm` the minute.
- Text inside square brackets is copied without the brackets, so `date_fmt(d, '[Day] D')` gives `Day 8`. Note that `D` inside the brackets is not a token.
- A single `m` or `s` is not a token. Write `mm` or `ss`.
- Only English month and weekday names are written. See [Known gaps](@/docs/known-gaps.md#dates-and-times).

## Parts of a date or time

### `year(value)`, `month(value)`, `day(value)`, `weekday(value)`

`(text) -> number`. The year; the month (1 to 12); the day of the month (1 to 31); and the weekday, from 1 for Monday to 7 for Sunday (ISO numbering).

- `weekday('2026-10-08')` is `4` (a Thursday).
- `year(render.date)` is the year of the render.
- A time-only text is error 3105.

### `hour(value)`, `minute(value)`

`(text) -> number`. The hour (0 to 23) and the minute (0 to 59). A date-only text gives `0`.

- `hour(render.time)` is the hour of the render, in the project's time zone.

## Arithmetic

### `add_days(value, n)`

`(text, number) -> text`. Adds `n` days to a date or a date-time. `n` is floored. The result has the same form as the input: a date stays a date, and a date-time keeps its `Z`.

- `add_days('2026-10-08', 30)` is `2026-11-07`.
- A time-only text is error 3105. So is a result outside years 1 to 9999.

Example: a date a fixed number of days from the card's release date, shown as text:

```json
"text": "{date_fmt(add_days(release, 14), 'D MMMM YYYY')}"
```

### `days_between(a, b)`

`(text, text) -> number`. The whole number of days from the date part of `a` to the date part of `b`: `b - a`. The result is negative when `b` is earlier.

- `days_between('2026-10-15', '2026-12-25')` is `71`.
- `days_between(render.date, release)` counts the days until a release date.
- A time-only text is error 3105.

### `add_hours(value, h)`

`(text, number) -> text`. Adds `h` hours to a date or a date-time, and gives a date-time as `YYYY-MM-DDTHH:MM:SS`. A date counts as midnight. A fractional `h` is rounded to whole seconds. The `Z` of the input is kept.

- `add_hours('2026-10-08T22:00:00Z', 5)` is `2026-10-09T03:00:00Z`.
- `add_hours('2026-10-08', 5)` is `2026-10-08T05:00:00`.
- A time-only text is error 3105. So is a result outside years 1 to 9999.

Example: the UTC time of the render shown in another zone. The offset is fixed, so this does not follow daylight saving time either:

```json
"text": "Live at {date_fmt(render.now, 'HH:mm')} UTC, {date_fmt(add_hours(render.now, -5), 'HH:mm')} in New York"
```

`render.now` is always UTC, so this works whatever `utc_offset` is set to.
