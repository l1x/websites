---
title: "Data-cat"
date: 2019-11-01T14:31:21+02:00
description: "Deploying DataDog for a large scale infrastructure"
number: 3
tags:
    - python
    - datadog
    - monitoring
    - cloud
---

# Data-cat

Deploying DataDog for a large scale infrastructure


## Definitions

- Geographic Regions
- Stages
- Applications

### Geographic Regions

Matches the definitions of AWS Regions. It can be used for GCP or on-prem datacenter as well.

### Stages

Different stages of application deployments, usually: dev, qa, prod.

### Applications

A service that provides a distinct business functionality.

## Goals

- having all monitors and dashboards in version control
- having all monitors templated
- being able to address smaller parts of the infrastructure

## Implementation

4 files represent the DataDog configuration for the whole infrastructure.

- infrastructure.yaml

It contains the logical grouping of applications into stages and regions. The relations are always N:M. 1 region can contain many stages and many applications in each stage.

- region.yaml

Defaults for a certain region (region).

- stage.yaml

Defaults for a certain stage (region, stage).

- application.yaml

Configuration that is specific for a certain application (region, stage, application).

### Generating infrastructure.yaml

I recently discovered [Dhall](https://dhall-lang.org) that seems like the perfect fit to write the infrastructure in and than generate the YAML files.

The type safe definitions looks like the following:

```Haskell
let keyValue =
        λ(k : Type)
      → λ(v : Type)
      → λ(mapKey : k)
      → λ(mapValue : v)
      → { mapKey = mapKey, mapValue = mapValue }

let ApplicationConfig : Type = { created_at : Text }

let Application = < etcd | postgresql | hadoop >
let Applications = Prelude.Map.Type Application ApplicationConfig
let application = keyValue Application ApplicationConfig

let Stage = < dev | qa | prod >
let Stages = Prelude.Map.Type Stage Applications
let stage = keyValue Stage Applications

let AwsRegion = < us-east-1 | eu-central-1 | eu-west-1 >
let AwsRegions = Prelude.Map.Type AwsRegion Stages
let awsRegion = keyValue AwsRegion Stages
```

After having these definitions we can create the infrastructure:

```Haskell
in  [ awsRegion AwsRegion.us-east-1
        [ stage Stage.dev
             [ application Application.hadoop { created_at = "2019-11-04T09:00:00Z" }
             , application Application.etcd { created_at = "2019-11-04T09:00:00Z" }
             ]
        , stage Stage.qa
             [ application Application.hadoop { created_at = "2019-11-04T09:00:00Z" }
             , application Application.etcd { created_at = "2019-11-04T09:00:00Z" }
             ]
        ]

    , awsRegion AwsRegion.eu-west-1
        [ stage Stage.dev
             [ application Application.hadoop { created_at = "2019-11-04T09:00:00Z" }
             , application Application.etcd { created_at = "2019-11-04T09:00:00Z" }
             ]
        ]
    , awsRegion AwsRegion.eu-central-1
        [ stage Stage.dev
            [ application Application.hadoop { created_at = "2019-11-04T09:00:00Z" }
            , application Application.etcd { created_at = "2019-11-04T09:00:00Z" }
            ]
        ]
    ]
```

Generating the YAML:

```bash
dhall-to-yaml --file infrastructure.dhall > infrastructure.yaml
```

### Generating the folder structure

```Bash
python3 gen.py
region: eu-central-1, stage: dev
region: eu-central-1, stage: dev, app: etcd
region: eu-central-1, stage: dev, app: hadoop
region: eu-west-1, stage: dev
region: eu-west-1, stage: dev, app: etcd
region: eu-west-1, stage: dev, app: hadoop
region: eu-west-1, stage: prod
region: eu-west-1, stage: prod, app: etcd
region: eu-west-1, stage: prod, app: hadoop
```

### Templates

Templates folder has the monitor templates.

Example template:

```YAML
---
name: High CPU load on application_name:{application_name} stage:{stage} {{{{host.name}}}} / {{{{host.ip}}}}
tags:
  - application_name:{application_name}
  - stage:{stage}
  - region:{region}
type: metric alert
query: avg(last_5m):avg:system.load.norm.5{{application_name:{application_name},stage:{stage}}} by {{host}} > {critical_threshold}
message: >-2
  High CPU load on application_name:{application_name} stage:{stage} {{{{host.name}}}} / {{{{host.ip}}}} for 5 consecutive minutes on this node.
  Url: https://wd-global-prod.datadoghq.com/monitors/{monitor_id}
  {slack_notification_channel}
monitor_options:
  notify_audit: False
  locked: False
  timeout_h: 0
  silenced: {{}}
  include_tags: True
  require_full_window: True
  new_host_delay: 300
  notify_no_data: False
  renotify_interval: 0
  escalation_message: >-2
    CPU load is still damn high.
  thresholds:
    critical: {critical_threshold}
    warning: {warning_threshold}
```

This gets rendered using Python format and converted to a dict that used to talk to the DataDog API.

### Defaults and specifics

Defaults are stage wide settings specifics are specific to a single application (in a region & stage).

### Tags alignment

For all of these above to work together nicely there is a dependency on tags being deployed every node, ELB, etc., so that we can reference those in monitors and dashboards.

## Deployment

I gave up on Conda and now just using venv from Python.

```Bash
/usr/local/opt/python3/bin/python3 -m venv venv
. venv/bin/activate.fish #or the shell you are using
pip install --upgrade pip
pip install --upgrade toml pyyaml
```

### Deploying monitors

Deploying a whole stage:

```bash
./data-cat/data-cat.py deploy-monitors -r eu-west-1 -s qa
```

Deploying a single application:

```bash
./data-cat/data-cat.py deploy-monitors -r eu-west-1 -s qa -a etcd
```

### Deploying dashboards

Deploying a whole stage:

```bash
./data-cat/data-cat.py deploy-dashboards -r eu-west-1 -s qa
```

Deploying a single application:

```bash
./data-cat/data-cat.py deploy-dashboards -r eu-west-1 -s qa -a etcd
```
## What to monitor

Following [Brendan Gregg's use method](http://www.brendangregg.com/usemethod.html) and the suggested things to monitor:

- CPUs: sockets, cores, hardware threads (virtual CPUs)
- Memory: capacity
- Network interfaces
- Storage devices: I/O, capacity
- Controllers: storage, network cards
- Interconnects: CPUs, memory, I/O

How to monitor it (examples):

- utilization: as a percent over a time interval. eg, "one disk is running at 90% utilization"
- saturation: as a queue length. eg, "the CPUs have an average run queue length of four"
- errors: scalar counts. eg, "this network interface has had fifty late collisions"

