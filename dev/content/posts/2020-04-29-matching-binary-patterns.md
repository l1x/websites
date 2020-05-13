---
title: "Matching binary patterns"
date: 2020-04-29T14:31:21+02:00
description: "Using binary pattern matching for working with network protocols"
tags:
    - erlang
    - beam
    - elixir
---
# Matching binary patterns

In Erlang, it is easy to construct binaries and bitstrings and matching binary patterns. I was running into Mitchell Perilstein's excellent work on NTP with Erlang and I thought I am going to use this to explain how bitstrings and binaries work in Erlang. 

Two concepts:

- A bitstring is a sequence of zero or more bits, where the number of bits does not need to be divisible by 8.

- A binary is when the number of bits is divisible by 8.

The syntax is as follows:

```erlang
 <<B1, B2, ... Bn>>
```

Each element specifies a certain segment of the bitstring. A segment is a set of contiguous bits of the binary (not necessarily on a byte boundary). 

A real-life example:

```erlang
 << 0:2, 4:3, 3:3,  0:(3*8 + 3*32 + 4*64) >>.
```

Let's unpack a bit of what is going on here. For this, it is worth knowing the whole syntax.

```erlang
<< Value:Size/TypeSpecifierList, Value:Size/TypeSpecifierList, ...>>
```

Or alternatively:

```erlang
Ei = Value |
     Value:Size |
     Value/TypeSpecifierList |
     Value:Size/TypeSpecifierList
```

This means in the real-life example, we have 0 as the value, 2 is the size (2 bits), four as a value, 3 bits as size, and so on. We did not specify any of the type specifiers.

TypeSpecifierList is a list of type specifiers, in any order, separated by hyphens or dash (-). Default values are used for any omitted type specifier.

The following type specifiers are supported:

```erlang
Type = integer | float | binary | bytes | bitstring | bits | utf8 | utf16 | utf32
```

The default is an integer. bytes is a shorthand for binary and bits is a shorthand for bitstring. 

```erlang
Signedness= signed | unsigned
```

It only matters for matching and when the type is an integer. The default is unsigned.

```erlang
Endianness= big | little | native
```

Native-endian means that the endianness is resolved at load time to be either big-endian or little-endian, depending on what is native for the CPU that the Erlang machine is run on. Endianness only matters when the Type is either integer, utf16, utf32, or float. The default is big.

## A complete example

One of the simplest protocols out there is NTP. The header file looks like the following:

![Alt Text](https://dev-to-uploads.s3.amazonaws.com/i/imigpr35l0uhlkpbbh74.png)

This is used for both the request and the response. Let's craft the request first.

```erlang
create_ntp_request() ->
  << 0:2, 4:3, 3:3,  0:(3*8 + 3*32 + 4*64) >>.
```

Based on the header structure we can see that we have a 2-bit integer (Li), 3-bit integer version number, 3-bit integer mode, 8-bit stratum, 8-bit poll, 8-bit precision, and so on. We only need to set the first 3 values, the rest (376 bits) can be 0.

Let's try this in the wild.


### Creating the request

```erlang
1> Request = << 0:2, 4:3, 3:3,  0:(3*8 + 3*32 + 4*64) >>.
<<35,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,...>>
```

### Sending and receiving

We can use Erlang's built-in functions for this one, gen_udp has a pretty comprehensive low-level UDP implementation, that can do all we want.

```erlang

% open a local socket, 0 indicates that it will pick a random local port
% active=false means we need to receive ourselves

2> {ok, Socket} = gen_udp:open(0, [binary, {active, false}]),
2> gen_udp:send(Socket, "0.europe.pool.ntp.org", 123, Request),
2> {ok, {_Address, _Port, Resp}} = gen_udp:recv(Socket, 0, 500).
{ok,{{212,59,0,1},
     123,
     <<36,2,0,231,0,0,0,110,0,0,0,25,212,59,3,3,226,84,62,89,
       208,192,202,156,...>>}}
```

### Processing the response, first few bits

The response is just a binary that we need to slice and dice, similarly how we created the request.

```erlang
3> Resp.
<<36,2,0,231,0,0,0,110,0,0,0,25,212,59,3,3,226,84,62,89,
  208,192,202,156,0,0,0,0,0,...>>
```

First, we can just get the first few bits.

```erlang
4> << Li:2, Version:3, Mode:3, _rest/binary >> = Resp.
<<36,2,0,231,0,0,0,110,0,0,0,25,212,59,3,3,226,84,62,89,
  208,192,202,156,0,0,0,0,0,...>>
5> {li, Li, version, Version, mode, Mode}.
{li,0,version,4,mode,4}
```
It works.

The rest of the header a bit more tricky but with the bitstring syntax, it is easy to manage.

### Processing the response, the rest

Finally matching all the mandatory fields. 

```erlang
6>   << LI:2, Version:3, Mode:3, Stratum:8, Poll:8/signed, Precision:8/signed,
6>      RootDel:32, RootDisp:32, R1:8, R2:8, R3:8, R4:8, RtsI:32, RtsF:32,
6>      OtsI:32, OtsF:32,   RcvI:32, RcvF:32, XmtI:32, XmtF:32 >> = Resp.
<<36,2,0,231,0,0,0,110,0,0,0,25,212,59,3,3,226,84,62,89,
  208,192,202,156,0,0,0,0,0,...>>
```

Making sense of these values requires a bit more legwork. First, we need a utility function for binary fractions.

In Erlang, function arity differentiates functions so we can do the following:

```erlang
binfrac(Bin) ->
  binfrac(Bin, 2, 0).
binfrac(0, _, Frac) ->
  Frac;
binfrac(Bin, N, Frac) ->
  binfrac(Bin bsr 1, N*2, Frac + (Bin band 1)/N).
```

With this function, we can implement the one that processes the response and returns the values we are interested in.


```erlang
% 2208988800 is the offset (1900 to Unix epoch)

process_ntp_response(Ntp_response) ->
  << LI:2, Version:3, Mode:3, Stratum:8, Poll:8/signed, Precision:8/signed,
     RootDel:32, RootDisp:32, R1:8, R2:8, R3:8, R4:8, RtsI:32, RtsF:32,
     OtsI:32, OtsF:32,   RcvI:32, RcvF:32, XmtI:32, XmtF:32 >> = Ntp_response,
  {NowMS, NowS, NowUS} = erlang:timestamp(),
  NowTimestamp = NowMS * 1.0e6 + NowS + NowUS/1000,
  TransmitTimestamp = XmtI - 2208988800 + binfrac(XmtF),
  { {li, LI}, {vn, Version}, {mode, Mode}, {stratum, Stratum}, {poll, Poll}, {precision, Precision},
    {rootDelay, RootDel}, {rootDispersion, RootDisp}, {referenceId, R1, R2, R3, R4},
    {referenceTimestamp, RtsI - 2208988800 + binfrac(RtsF)},
    {originateTimestamp, OtsI - 2208988800 + binfrac(OtsF)},
    {receiveTimestamp,   RcvI - 2208988800 + binfrac(RcvF)},
    {transmitTimestamp,  TransmitTimestamp},
    {clientReceiveTimestamp, NowTimestamp},
    {offset, TransmitTimestamp - NowTimestamp} }.
```

And wit that we can just process the response.

```erlang
{{li,0},
 {vn,4},
 {mode,4},
 {stratum,2},
 {poll,3},
 {precision,-24},
 {rootDelay,9},
 {rootDispersion,140},
 {referenceId,85,158,25,75},
 {referenceTimestamp,1588186010.7517557},
 {originateTimestamp,-2208988800},
 {receiveTimestamp,1588186048.3557627},
 {transmitTimestamp,1588186048.8841336},
 {clientReceiveTimestamp,1588186606.531},
 {offset,-557.6468663215637}}
```

Please note, this is the first step in the NTP workflow and does not implement the complete NTP protocol. We do not take into consideration a bunch of details.

Next time we might look into how to implement a simple server (like DNS) in Erlang.


Michael's original work:

https://github.com/mnp/erlang-ntp

Up to date version and Elixir port:

https://gist.github.com/l1x/b0a7f844b283ac08e3125d1ba6e81eeb
