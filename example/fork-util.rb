$LOAD_PATH.unshift "lib"

require 'rinda/rinda'

class EasyTuplespace
  def self.start
    et = new
    yield et
  ensure
    et.cleanup
  end

  def initialize
    @pids = []
  end
  
  def cleanup
    @pids.each do |pid|
      Process.waitpid pid
    end

    Process.kill "TERM", @pid
  end
  
  def server
    rd, wr = IO.pipe

    @pid = fork do
      rd.close
      require 'rinda/tuplespace'
      ts = Rinda::TupleSpace.new
      yield ts
      DRb.start_service(nil, ts)
      wr.puts DRb.uri
      wr.close
      DRb.thread.join
    end

    wr.close
    @uri = rd.gets.chomp
    rd.close
  end

  def client
    @pids << fork do
      DRb.start_service
      ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(@uri))
      yield ts
    end
  end
  
  def local
    DRb.start_service unless DRb.primary_server ## ok?
    ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(@uri))
    yield ts
  end
end

# Using the above, the following code is simpler. Many examples can be
# refactored in this way.

answer =
  EasyTuplespace.start do |et|
    et.server do |ts|
      ts.write [:foo, 42]
    end

    n = 3
    n.times do
      et.client do |ts|
        _, x = ts.take [:foo, nil]
        p x
        ts.write [:foo, x + 1]
      end
    end

    et.local do |ts|
      ts.read [:foo, nil]
    end
  end

puts "The answer is: #{answer}"
