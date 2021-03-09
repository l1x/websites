---
title: Compressing data with Parquet
date: 2021-03-08T20:38:21+01:00
draft: false
description: Compressing data with Parquet
tags:
  - parquet
  - sqlite
---

## Abstract

Many times I see that people use [Sqlite](https://www.sqlite.org/index.html) for distributing large datasets. When the use case is analytical (OLAP), there are often better options. We are going to investigate how much better we could do if we use something other than Sqlite. To make sure, I love Sqlite and use it a lot when a simple SQL single file database does it. For this particular use case, I think using [Parquet](http://parquet.apache.org/) is better suited. We are going to explore why.


## The rise of columnar formats

A while back, when [Facebook and Ohio State University investigated](https://research.fb.com/wp-content/uploads/2011/01/rcfile-a-fast-and-space-efficient-data-placement-structure-in-mapreduce-based-warehouse-systems.pdf) what would be the best option to store a large volume of data not too surprisingly, a columnar system came out to be the winner. There are many reasons why and I am not going to go into the details in this article because I do not have that much time. The point is that if you have repetition in your data, a columnar format can be compressed much better than a row-oriented format. On top of that, if you run a query that queries only a subset of the table fields, columnar can skip reading a whole lot of data that speeds up processing. Furthermore, a strong compression (gzip, brotli, zstd) is applied to columnar files, making those even smaller. Smaller files are preferable because the slowest part of data processing is still disk IO.


## The use case

While reading through a [post on HN](https://news.ycombinator.com/item?id=26371706), I have run into this comment from [zomglings](https://news.ycombinator.com/user?id=zomglings) explaining that they got a dataset that is an export of some Github data.


> The dataset for a single crawl comes in at about 60GB. We uploaded the data to Kaggle because we thought it would be a good place for people to work with > the data. Unfortunately, the Kaggle notebook experience is not tailored to such large datasets. Our dataset is in an SQLite database. It takes a long time > for the dataset to load into Kaggle notebooks, and I don't think they are provisioned with SSDs as queries take a long time. Our best workaround to this
> is to partition into 3 datasets on Kaggle - train, eval, and development, but it will be a pain to manage this for every update, especially as we enrich
> the dataset with results of static analysis, etc.



I was wondering if we could do better than the SQLite version.

## The initial dataset

After downloading the sample dataset from [Kaggle](https://www.kaggle.com/simiotic/github-code-snippets-development-sample) I started to explore a bit.

```SQL
 sqlite3 -header -csv -readonly -header snippets-dev.db '.schema snippets'
CREATE TABLE snippets (
    id INTEGER PRIMARY KEY,
    snippet TEXT NOT NULL,
    language TEXT NOT NULL,
    repo_file_name TEXT,
    github_repo_url TEXT,
    license TEXT,
    commit_hash TEXT,
    starting_line_number INTEGER,
    chunk_size INTEGER,
    UNIQUE(commit_hash, repo_file_name, github_repo_url, chunk_size, starting_line_number)
);
CREATE INDEX snippets_github_repo_url on snippets(github_repo_url);
CREATE INDEX snippets_license on snippets(license);
CREATE INDEX snippets_language on snippets(language);
```


The first thing I found that there is a weird spacing going on with the commit_hash column:

```SQL
sqlite> SELECT commit_hash FROM snippets LIMIT 10;
000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608

000427352ad89da7fb4325037c116a3b06745608
```

I realized that there is a trailing newline for each commit hash. I quickly fixed that.

```SQL
sqlite> UPDATE snippets SET commit_hash = REPLACE(commit_hash, CHAR(10), '');
sqlite> UPDATE snippets SET commit_hash = REPLACE(commit_hash, CHAR(13), '');
```

Now the commit hashes looked ok.

```SQL
sqlite> SELECT commit_hash FROM snippets LIMIT 10;
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
000427352ad89da7fb4325037c116a3b06745608
```

Before I continued working with the dataset, I quickly vacuumed that database:

```SQL
sqlite> PRAGMA auto_vacuum = FULL;
sqlite> VACUUM;
```

It reduced the size by 100MB.

Next step I just looked into the fields (skipping the snippet part):


```SQL
sqlite> SELECT id, language, repo_file_name, github_repo_url, license, commit_hash, starting_line_number, chunk_size FROM snippets LIMIT 10;
id          language    repo_file_name            github_repo_url                   license     commit_hash                               starting_line_number  chunk_size
----------  ----------  ------------------------  --------------------------------  ----------  ----------------------------------------  --------------------  ----------
491         DOTFILE     NodeBB/NodeBB/.gitignore  https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  65                    5
512         UNKNOWN     NodeBB/NodeBB/LICENSE     https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  100                   5
584         UNKNOWN     NodeBB/NodeBB/LICENSE     https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  460                   5
610         UNKNOWN     NodeBB/NodeBB/LICENSE     https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  590                   5
627         JavaScript  NodeBB/NodeBB/test/group  https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  5                     5
638         JavaScript  NodeBB/NodeBB/test/group  https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  60                    5
646         JavaScript  NodeBB/NodeBB/test/group  https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  100                   5
673         JavaScript  NodeBB/NodeBB/test/group  https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  235                   5
690         JavaScript  NodeBB/NodeBB/test/group  https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  320                   5
714         JavaScript  NodeBB/NodeBB/test/group  https://github.com/NodeBB/NodeBB  GPL-3.0     21634e2681fb1329bcbab7b2e19418ebdb1012e1  440                   5
```

Based on this, I saw that there is a potentially high repetition in many of the fields. It can be quickly verified:


```SQL
SELECT
  COUNT (DISTINCT language) AS  language_dcnt
  , COUNT (DISTINCT repo_file_name) AS repo_file_name_dcnt
  , COUNT (DISTINCT github_repo_url) AS github_repo_url_dcnt
  , COUNT (DISTINCT license) AS license_dcnt
  , COUNT (DISTINCT commit_hash) AS commit_hash_dcnt
  , COUNT (DISTINCT starting_line_number) AS starting_line_number_dcnt
  , COUNT (DISTINCT chunk_size) AS chunk_size_dcnt
FROM snippets LIMIT 1;

language_dcnt
-------------
21

repo_file_name_dcnt
-------------------
1150333

github_repo_url_dcnt
--------------------
1621

license_dcnt
------------
21

commit_hash_dcnt
----------------
1621

starting_line_number_dcnt
-------------------------
27833

chunk_size_dcnt
---------------
1
```


## Exporting data

Based on the previous distinct counts, I decided to export the data the following way:


```SQL
sqlite3 -header -csv -readonly snippets-dev.db 'SELECT * FROM snippets ORDER BY chunk_size, license, language, github_repo_url, commit_hash' > test1.csv
```

Using the freshly exported file, I can now convert the CSV to Parquet with default settings first.

```Python
import pandas as pd
import sys
df = pd.read_csv(sys.argv[1])
df.to_parquet(sys.argv[2])
```

```bash
python par.py test1.csv test1.parquet
```

The results are already good:

```bash
2.9G Mar  8 08:37 snippets-dev.db
427M Mar  8 14:05 test1.parquet
```

Now we can import the CSV file into a DataFrame using Python:

```Python
import pandas as pd
import sys

df = pd.read_parquet(sys.argv[1], engine='pyarrow')
```

Then I remembered that the default compression for Parquet in the Python library is still snappy for some weird reason. Changing that to gzip, we can get much better.

```Python
df.to_parquet(sys.argv[2], compression='gzip')
```

After creating another version, compressing it with gzip, this time the result is much better.

```bash
265M Mar  8 17:28 test1.gzip.parquet
```

Results:

```bash
Sqlite:           ||||||||||||||||||||||||||||||  3000MB 100%
Parquet(Snappy):  ||||                            427MB  14.2%
Parquet(Gzip):    |||                             265MB  8.83%
```

## Closing

91.17% reduction with Parquet is not that bad. If you need some help with data engineering or have any performance related question (especially querying large datasets) feel free to reach out. See the links below.


