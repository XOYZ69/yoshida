+++
title = "Stats"
description = "Public numbers about yoshida: stars, downloads and repository traffic, collected from GitHub once a day."
template = "stats.html"
+++

## Where these numbers come from

Everything on this page is counted by GitHub, not by yoshida. A scheduled job asks GitHub's API once a day for the repository's stars, forks, release downloads and, when the maintainer has allowed it, page views and clones of the repository. It stores the answer as one file on the [`stats` branch](https://github.com/XOYZ69/yoshida/tree/stats), and this page reads that file. The history starts on the day the job first ran, because GitHub itself keeps traffic for two weeks only.

The editor on this website has no server behind it. It measures nothing and sends nothing: your designs, card data and pictures stay in your browser. A self-hosted yoshida server can count its own usage, and those counts never leave that server. When its operator marks some of them as public and lists the instance here, they appear in a section of their own.
