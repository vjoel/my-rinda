require 'rinda/tuplespace'

module Rinda
  module TupleSpaceProxy::Establish
    def establish(pat_tuple, tuple, sec=nil)
      @ts.establish(pat_tuple, tuple, sec)
    end
  end

  module TupleSpace::Establish
    # Conditional write operation.
    # Adds +tuple+, but only if +pat_tuple+ doesn't match anything.
    # Returns the entry or false if no match.
    #
    def establish(pat_tuple, tuple, sec=nil)
      pat_template = WaitTemplateEntry.new(self, pat_tuple, nil)
      entry = create_entry(tuple, sec)
      synchronize do
        if @bag.find(pat_template)
          return false
        end
        
        if entry.expired?
          @read_waiter.find_all_template(entry).each do |template|
            template.read(tuple)
          end
          notify_event('write', entry.value)
          notify_event('delete', entry.value)
        else
          @bag.push(entry)
          start_keeper if entry.expires
          @read_waiter.find_all_template(entry).each do |template|
            template.read(tuple)
          end
          @take_waiter.find_all_template(entry).each do |template|
            template.signal
          end
          notify_event('write', entry.value)
        end
      end
      entry
    end
  end
end
