require "C:/Program Files (x86)/Knots Server/knots.rb"


begin  
   require 'win32/daemon'
   include Win32
   
   class DemoDaemon < Daemon
   
      def initialize
        @knots_server = Knots.new
      end
      
      
      # This method fires off before the +service_main+ mainloop is entered.
      # Any pre-setup code you need to run before your service's mainloop
      # starts should be put here. Otherwise the service might fail with a
      # timeout error when you try to start it.
      #
      def service_init         
      end
      
      # This is the daemon's mainloop. In other words, whatever runs here
      # is the code that runs while your service is running. Note that the
      # loop is not implicit.
      #
      # You must setup a loop as I've done here with the 'while running?'
      # code, or setup your own loop. Otherwise your service will exit and
      # won't be especially useful.
      #
      # In this particular case, I've setup a loop to append a short message
      # and timestamp to a file on your C: drive every 20 seconds. Be sure
      # to stop the service when you're done!
      #
      def service_main(*args)
         @knots_server.start
      end
   
      # This event triggers when the service receives a signal to stop. I've
      # added an explicit "exit!" here to ensure that the Ruby interpreter exits
      # properly. I use 'exit!' instead of 'exit' because otherwise Ruby will
      # raise a SystemExitError, which I don't want.
      #
      def service_stop        
        @knots_server.close_server if @knots_server
        exit!
      end
      
      # This event triggers when the service receives a signal to pause. 
      #
      def service_pause
      end
      
      # This event triggers when the service receives a signal to resume
      # from a paused state.
      #
      def service_resume
      end
   end

   # Create an instance of the Daemon and put it into a loop. I borrowed the
   # method name 'mainloop' from Tk, btw.
   #
   DemoDaemon.mainloop
   
   
rescue Exception => err
end