# benchmark with a large tuplespace.

$LOAD_PATH.unshift "lib"

require 'rinda/rinda'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  DRb.start_service(nil, ts)
  wr.puts DRb.uri
  DRb.thread.join
end

wr.close
uri = rd.gets.chomp

t0 = Process.times.to_a.inject{|s,x|s+x}

c1 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  
  n_elts = 100
  n_steps = 1000
  
  a = (0...n_elts).sort_by {rand}

  a.each do |i|
    ts.write([i]) ## should measure times separately from this setup
  end

  n_steps.times do |step|
    i = step % n_elts
    ts.take([i])
    ts.write([i])
  end
end

Process.wait c1

t1 = Process.times.to_a.inject{|s,x|s+x}

printf "time = %.2f\n", t1 - t0

Process.kill "TERM", server
