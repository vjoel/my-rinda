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

The patch adds Rinda::TupleSpaceProxy#take_fast, which avoids the two redundant marshal operations. The unit tests in the ruby source pass when calling this method instead of #take.

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


### TupleSpace primitives for nonblocking operations ###

#### 1. TupleSpace#take_any ####

**What it does**

Calling

```ruby
  take_any(tuple)
```

atomically removes the first matching tuple, if any. It does not block waiting for tuples. The return value is the tuples, or nil if no tuple matches.


**Why it is needed**

It is not possible to do this atomically with existing primitives. Also, some other tuplespace implementations eventually add this feature.


**Modularity**

The new code is entirely contained in two modules in a single separate file. These modules are included/extended to TupleSpace and TupleSpaceProxy as desired to add the take_all functionality.


**Examples**

See example/data-dependency.rb.


### TupleSpace primitives for conditional modifications ###

#### 1. TupleSpace#attempt ####

**What it does**

Calling

 ```ruby
  attempt(take_tuple, write_tuple, read_tuple=nil, sec=nil)
```

atomically attempts the following sequence of operations. Take _take_tuple_, without blocking. If successful, write _write_tuple_. Otherwise, read _read_tuple_, blocking if necessary.

The return value is a pair:

```ruby
  [ tuple, entry ]
```

The _tuple_ is the result of the take, if successful. Otherwise, it is
the result of the read.

The _entry_ is like the return value of #write, if the write happened.
Otherwise, _entry_ is nil.

if _read_tuple_ is nil and the #take fails, then the call returns
[nil, nil] without blocking.


**Why it is needed**

It is not possible to do this atomically with existing primitives and no locks. A client could #take a lock tuple, but then if the client dies, the tuplespace server may not find out about it for some time, leaving the lock set too long. It is also inefficient. The #attempt operation can be used for concurrent access without locking (i.e. "optimistic locking")--see example/optimist.rb.

The #attempt operation is a tuplespace analog of the compare-and-swap instruction[1]--see example/election.rb. Similar "conditional put" operations were recently added to a commercial tuplespace implementation[2] and to a commercial distributed key-value database[3].

[1] http://en.wikipedia.org/wiki/Compare-and-swap

[2] https://www.tibcommunity.com/blogs/activespaces

[3] http://en.wikipedia.org/wiki/Amazon_SimpleDB#Conditional_Put_and_Delete

In addition, combining operations in this way has some advantages:

1. it reduces network traffic

2. it eliminates risk of client failure between operations

**Modularity**

The new code is entirely contained in two modules in a single separate file. These modules are included/extended to TupleSpace and TupleSpaceProxy as desired to add the replace functionality.


**Examples**

See example/election.rb, example/optimist.rb, example/data-dependency.rb.

#### 2. TupleSpace#estasblish ####

**What it does**

Calling

 ```ruby
  establish(pat_tuple, tuple, sec=nil)
```

atomically attempts the following sequence of operations. If _pat_tuple_ matches something, write _tuple_ and return the entry, otherwise return false.

**Why it is needed**

It is not possible to do this atomically with existing primitives and no locks. Can be used to set the first tuple that matches a condition. Useful for a lock-free first-choice-wins protocol.

**Modularity**

The new code is entirely contained in two modules in a single separate file. These modules are included/extended to TupleSpace and TupleSpaceProxy as desired to add the replace functionality.

**Examples**

See example/establish.rb and example/election.rb.


## Tools ##

### tsh -- the tuplespace shell ###

Runs in two modes:

1. a tuplespace server in a forked child process and an irb in the parent process with a TupleSpaceProxy connected to the server, or

2. an irb as above connected to a tuplespace server given by a URL on the command line.

In each case, the _self_ of the irb session is the TupleSpaceProxy, so you can just type tuplespace commands directly.

See `bin/tsh --help` for details. A simple example:

*In terminal ONE* irb is running with the tuplespace server in a child process:

    $ bin/tsh
    tuplespace is at druby://myhostname:37393
    >> write [1,2]
    => #<DRb::DRbObject:0x007febb993ec28 @uri="druby://127.0.1.1:37393", @ref=70325200999800>
    >> read [nil, nil]
    => [1, 2]


*In terminal TWO* irb is running and connected to the server in terminsl one:

    $ bin/tsh druby://myhostname:37393
    >> take [1,2]
    => [1, 2]
