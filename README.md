my-rinda
========

My fixes and features for ruby's standard rinda library.

## Fixes ##

### Lost tuples when #take is interrupted ###

[ruby-trunk #8125](https://bugs.ruby-lang.org/issues/8125)

Rinda::TupleSpaceProxy prevents tuple loss during #take by exposing a "port" object on the client that the remote side (the tuplespace server) pushes to, instead of relying on the method return value. Pushing to the port fails if the process that called #take has exited, so the tuple will not be deleted from the tuplespace server.

However, if the process has not exited, and the thread that called #take was interrupted, the port still exists and accepts push requests (in the main drb thread). In this case the tuple is deleted on the server and not available on the client.

This is frequently a problem when using irb and manually interrupting take calls. It would also be a problem when using timeouts.

A concise reproduction of the problem is in example/thread-int.rb.

The fix replaces the port array with a custom object that rejects pushes if the call stack has been unwound.


### Slowness when taking large tuples ###

[ruby-trunk #8119](https://bugs.ruby-lang.org/issues/8119)

The purpose of Rinda::TupleSpaceProxy is to avoid losing tuples when a client disconnects during a #take call. This is implemented by sending the result value **twice**: first by pushing it to a client-side array, second by returning the result as a DRb response. If the first fails, then the #take is aborted, so that the tuple is not lost. In case of success, the client only uses the pushed value, not the response value.

This involves a total of **three** marshal operations by DRb: the push argument, the push return value (which is an array containing the push argument), and the #take return value. Only the first is necessary.

The following patch adds Rinda::TupleSpaceProxy#take_fast, which avoids the two redundant marshal operations. The unit tests in the ruby source pass when calling this method instead of #take.

The improvement is small when the object is simple. However, for complex objects, eliminating the redundant marshalling reduces network traffic and increases speed by a factor of 2. See example/bench.rb.


## Features ##

### TupleSpace primitives for atomic bulk operations ###

[ruby-trunk #8128](https://bugs.ruby-lang.org/issues/8128)

#### 1. TupleSpace#replace_all ####

**What it does**

Calling

 ```ruby
  replace_all(tuple, new_tuple, sec=nil)
```

atomically removes all tuples matching _tuple_ and writes _new_tuple_. It does not block waiting for tuples. The return value is a pair:

```ruby
  [ matching_tuples, entry ]
```

where _matching_tuples_ is like the return value of `read_all(tuple)` and
_entry_ is like the return value of `write(new_tuple)`.


**Why it is needed**

It is not possible to do this atomically with existing primitives. As noted in _The dRuby Book_, p. 176, "It isn't easy to represent a dictionary using TupleSpace." Essentially, the #[]= and #[] operations must take/write a global lock tuple.

Using #replace_all, it is easy to implement a key-value store without lock tuples. See example/key-value-store.rb for an example.


**Modularity**

The new code is entirely contained in two modules in a single separate file. These modules are included/extended to TupleSpace and TupleSpaceProxy as desired to add the replace_all functionality.


**Examples**

See example/key-value-store.rb and example/replace-all.rb.


#### 2. TupleSpace#take_all ####

**What it does**

Calling

```ruby
  take_all(tuple)
```

atomically removes all matching tuples. It does not block waiting for tuples. The return value is the array of tuples, like the return value of `read_all(tuple)`.


**Why it is needed**

It is not possible to do this atomically with existing primitives, though in this case atomicity may not be important. More importantly, it is not possible to do this efficiently with existing primitives. The best approximation would be an unbounded sequence of #take calls.


**Modularity**

The new code is entirely contained in two modules in a single separate file. These modules are included/extended to TupleSpace and TupleSpaceProxy as desired to add the take_all functionality.


**Examples**

See example/take-all.rb.


## Tools ##

### tsh -- the ruplespace shell ###

Runs in two modes:

1. a tuplespace server in a forked child process and an irb in the parent process with a TupleSpaceProxy connected to the server, or

2. an irb as above connected to a tuplespace server given by a URL on the command line.

See `bin/tsh --help` for details. A simple example:

*In terminal ONE*

    $ bin/tsh
    tuplespace is at druby://myhostname:37393
    >> write [1,2]
    => #<DRb::DRbObject:0x007febb993ec28 @uri="druby://127.0.1.1:37393", @ref=70325200999800>
    >> read [nil, nil]
    => [1, 2]


*In terminal TWO*

    $ bin/tsh druby://myhostname:37393
    >> take [1,2]
    => [1, 2]