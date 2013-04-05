require 'rinda/tuplespace'

module Rinda
  module TupleSpaceProxy::TakeAny
    def take_any(tuple)
      port = []
      @ts.move_any(DRbObject.new(port), tuple)
      port[0]
    end
  end

  module TupleSpace::TakeAny
    # Atomically remove a matching tuple, if any, and return it; never block
    # waiting for a tuple, return nil instead.
    def take_any(tuple)
      move_any(nil, tuple)
    end
    
    def move_any(port, tuple)
      template = WaitTemplateEntry.new(self, tuple, nil)
      synchronize do
        entry = @bag.find(template)
        value = entry && entry.value
        port.push(value) if port
        if entry
          @bag.delete(entry)
          notify_event('take', value)
        end
        return value
      end
    end
  end
end
