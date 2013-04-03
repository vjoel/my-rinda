require 'rinda/tuplespace'

module Rinda
  module TupleSpaceProxy::Attempt
    def attempt(take_tuple, write_tuple, read_tuple=nil, sec=nil)
      @ts.attempt(take_tuple, write_tuple, read_tuple, sec)
    end
  end

  module TupleSpace::Attempt
    # Attempt to take +take_tuple+, without blocking. If successful, write
    # +write_tuple+. Otherwise, read +read_tuple+, blocking if necessary.
    #
    # Returns a pair:
    #
    #   [ tuple, entry ]
    #
    # The +tuple+ is the result of the take, if successful. Otherwise, it is
    # the result of the read.
    #
    # The +entry+ is like the return value of #write, if the write happened.
    # Otherwise, +entry+ is nil.
    #
    # if +read_tuple+ is nil and the #take fails, then the call returns
    # [nil, nil] without blocking.
    #
    def attempt(take_tuple, write_tuple, read_tuple=nil, sec=nil)
      take_template = WaitTemplateEntry.new(self, take_tuple, nil)
      if read_tuple
        read_template = WaitTemplateEntry.new(self, read_tuple, sec)
        yield(read_template) if block_given?
      end
      
      new_entry = create_entry(write_tuple, sec)
      synchronize do
        entry = @bag.find(take_template)
        
        if entry
          # take(take_tuple)
          @bag.delete(entry)
          value = entry.value
          notify_event('take', value)
          
          # write(write_tuple)
          if new_entry.expired?
            @read_waiter.find_all_template(new_entry).each do |templ|
              templ.read(new_tuple)
            end
            notify_event('write', new_entry.value)
            notify_event('delete', new_entry.value)
          
          else
            @bag.push(new_entry)
            start_keeper if new_entry.expires
            @read_waiter.find_all_template(new_entry).each do |templ|
              templ.read(new_tuple)
            end
            @take_waiter.find_all_template(new_entry).each do |templ|
              templ.signal
            end
            notify_event('write', new_entry.value)
          end

          return DRb::DRbArray.new [value, new_entry]
          
        else
          if read_tuple
            # read(read_tuple) (blocking)
            entry = @bag.find(read_template)
            return [entry.value, nil] if entry
            raise RequestExpiredError if read_template.expired?

            begin
              @read_waiter.push(read_template)
              start_keeper if read_template.expires
              read_template.wait
              raise RequestCanceledError if read_template.canceled?
              raise RequestExpiredError if read_template.expired?
              return [read_template.found, nil]
            ensure
              @read_waiter.delete(read_template)
            end
          
          else
            return [nil, nil]
          end
        end
      end
    end
  end
end
