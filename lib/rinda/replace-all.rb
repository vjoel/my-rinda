require 'rinda/tuplespace'

module Rinda
  module TupleSpaceProxy::ReplaceAll
    def replace_all(tuple, new_tuple, sec=nil)
      @ts.replace_all(tuple, new_tuple, sec)
    end
  end

  module TupleSpace::ReplaceAll
    # Atomically remove all matching tuples and write the new_tuple.
    # Does not block waiting for tuples. Returns a pair:
    #   [ matching_tuples, entry ]
    # where +matching_tuples+ is like the return value of read_all and
    # +entry+ is like the return value of #write.
    def replace_all(tuple, new_tuple, sec=nil)
      template = WaitTemplateEntry.new(self, tuple, nil)
      new_entry = create_entry(new_tuple, sec)
      synchronize do
        entries = @bag.find_all(template) ## better: delete_all
        entries.each do |entry|
          @bag.delete(entry)
        end
        values = entries.map {|e| e.value}
        values.each do |value|
          notify_event('take', value)
        end

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
        DRb::DRbArray.new [values, new_entry]
      end
    end
  end
end
