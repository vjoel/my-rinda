require 'rinda/tuplespace'

module Rinda
  module TupleSpaceProxy::TakeAll
    def take_all(tuple)
      port = []
      @ts.move_all(DRbObject.new(port), tuple)
      port
    end
  end

  module TupleSpace::TakeAll
    # Atomically remove all matching tuples and return the array; never block
    # waiting for tuples.
    # The result may be an empty array, but will never be nil.
    def take_all(tuple)
      move_all(nil, tuple)
    end
    
    def move_all(port, tuple)
      template = WaitTemplateEntry.new(self, tuple, nil)
      synchronize do
        entries = @bag.find_all(template)
        values = entries.map {|e| e.value}
        port.push(*values) if port
        entries.each do |entry|
          @bag.delete(entry) ## better: delete_all
        end
        values.each do |value|
          notify_event('take', value)
        end
        return values
      end
    end
  end
end
