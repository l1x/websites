---
title: Why I chose Fsharp for our AWS Lambda project
description: Writing AWS Lambda functions in F#
date: 2020-05-08T14:31:21+02:00
tags: 
  - fsharp
  - dotnet
  - aws
  - lambda
  - serverless
draft: false
---

# Why I chose Fsharp for our AWS Lambda project

## The dilema

I wanted to create a simple Lambda function to be able to track how our users use the website and the web application without a 3rd party and a ton of external dependencies, especially avoiding 3rd party Javascript and leaking out data to mass surveillance companies. The easiest way is to use a simple tracking 1x1 pixel or beacon that collects just the right amount of information (strictly non-PII). This gives us enough information for creating basic funnels, that covers most of our needs.

## First Option: Python

My default language (regardless of what I am going to work on) is Python. It has many great features and it is easy to prototype in it and the performance is great once you are using a C++ or Rust backed library. This also introduces a few issues when you are trying to deploy to AWS Lambda. I develop mainly on macOS and Lambda runs on Linux. Once you need to compile anything it is hard to get it right because Python does not support compiling to a different platform.

[https://stackoverflow.com/questions/44490197/how-to-cross-compile-python-packages-with-pip]()

I was running into packaging issues because on Mac it is not easy to cross-compile and package Python code, maybe if I would create a proper package but I could not find a simple way without Docket. It would extremely valuable if Python had a way to compile a package that you upload to AWS and it works, 100%. I was running into problems that it was working on my Mac and did not work on AWS. I haven't had enough time to investigate. 

## Second Option: Rust

Rust became the rising star over the years and I try to use it as much as possible with mixed success. My biggest problem is with Rust the low-level nature and the quirky features, that are hard to reason about. From AWS Lambda examples:

```Rust
use lambda::handler_fn;
use serde_json::Value;

type Error = Box<dyn std::error::Error + Send + Sync + 'static>;

#[tokio::main]
async fn main() -> Result<(), Error> {
    let func = handler_fn(func);
    lambda::run(func).await?;
    Ok(())
}

async fn func(event: Value) -> Result<Value, Error> {
    Ok(event)
}
```

Do you think that everybody understands immediately what is going on here? I don't. Even if I do, how am I going to explain this to a junior dev? How long does it take to get productive in Rust? I know that for extreme performance we might need this, but our current application is super happy without Rust, we do not have a performance problem. It is more important that developers are productive and the code is super simple to understand.

## And the winner is: Fsharp

Member of the ML family, running on the .NET platform, pretty mature ecosystem. Developers can pick up quickly, especially the way we use it, simple functions will do with small types. The performance is great out of the box, in case you need more you have great tooling around it.

Our handler function:

```Fsharp
  let handler(request:APIGatewayProxyRequest) =

    let httpResource =
      match isNull request.Resource with
      | true  -> "None"
      | _     -> request.Resource

    let httpMethod =
      match isNull request.HttpMethod with
      | true  -> "None"
      | _     -> request.HttpMethod

    let httpHeadersAccept =
      match isNull request.Headers with
      | true  -> "None"
      | _     -> getOrDefault request.Headers  "Accept" "None"

    let acceptImage =
      let pattern = @"image/"
      let m = Regex.Match(httpHeadersAccept, pattern)
      m.Success

    let log = String.Format("{0} :: {1} :: {2}", httpResource, httpMethod, httpHeadersAccept)
    LambdaLogger.Log(log)
    match (httpResource, httpMethod, httpHeadersAccept, acceptImage) with
    | ("/trck",         "POST", "application/json", _    ) -> trckPost(request)
    | ("/trck",         "GET",  _,                  true ) -> trckGet(request)
    | ("/trck/{image}", "GET",  _,                  true ) -> trckGet(request)
    | ("/echo",         "GET",  _,                  _    ) -> echoGet(request)
    | (_,               _,      _,                  _    ) -> notFound(request)
```

Pretty readable code, sure, you have to deal with nulls but Fsharp gives you great tooling around it. It took me probably a couple of days from having zero experience with .NET to deploy the first working API that has all of the functionality we are looking for. I might not have idiomatic Fsharp yet, but I am happy with the results so far. In the last couple of weeks, I have written many small tools in Fsharp, mostly dealing with the AWS APIs, I like it so much that I replaced my Python first approach and I go and try to implement everything in F# first. I can develop at the same pace as with Python but the result is much more solid code and easier on deployments (goodbye pip). 

I think Fsharp is exactly in the sweet spot of programming languages, good enough performance, nice enough features, and a ton of great libraries. It does not have the problem that Python suffers, you can create a single zip that will work on all platforms. It also free from exposing the low-level details that I do not want to care about in business domain code, what Rust does.
