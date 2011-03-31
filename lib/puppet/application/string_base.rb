require 'puppet/application'
require 'puppet/string'

class Puppet::Application::StringBase < Puppet::Application
  should_parse_config
  run_mode :agent

  option("--debug", "-d") do |arg|
    Puppet::Util::Log.level = :debug
  end

  option("--verbose", "-v") do
    Puppet::Util::Log.level = :info
  end

  option("--format FORMAT") do |arg|
    @format = arg.to_sym
  end

  option("--mode RUNMODE", "-r") do |arg|
    raise "Invalid run mode #{arg}; supported modes are user, agent, master" unless %w{user agent master}.include?(arg)
    self.class.run_mode(arg.to_sym)
    set_run_mode self.class.run_mode
  end


  attr_accessor :string, :action, :type, :arguments, :format
  attr_writer :exit_code

  # This allows you to set the exit code if you don't want to just exit
  # immediately but you need to indicate a failure.
  def exit_code
    @exit_code || 0
  end

  # Override this if you need custom rendering.
  def render(result)
    render_method = Puppet::Network::FormatHandler.format(format).render_method
    if render_method == "to_pson"
      jj result
      exit(0)
    else
      result.send(render_method)
    end
  end

  def preinit
    super
    trap(:INT) do
      $stderr.puts "Cancelling String"
      exit(0)
    end

    # We need to parse enough of the command line out early, to identify what
    # the action is, so that we can obtain the full set of options to parse.

    # TODO: These should be configurable versions, through a global
    # '--version' option, but we don't implement that yet... --daniel 2011-03-29
    @type   = self.class.name.to_s.sub(/.+:/, '').downcase.to_sym
    @string = Puppet::String[@type, :current]
    @format = @string.default_format

    # Now, walk the command line and identify the action.  We skip over
    # arguments based on introspecting the action and all, and find the first
    # non-option word to use as the action.
    action = nil
    cli    = command_line.args.dup # we destroy this copy, but...
    while @action.nil? and not cli.empty? do
      item = cli.shift
      if item =~ /^-/ then
        option = @string.options.find { |a| item =~ /^-+#{a}\b/ }
        if option then
          if @string.get_option(option).takes_argument? then
            # We don't validate if the argument is optional or mandatory,
            # because it doesn't matter here.  We just assume that errors will
            # be caught later. --daniel 2011-03-30
            cli.shift unless cli.first =~ /^-/
          end
        else
          raise ArgumentError, "Unknown option #{item.sub(/=.*$/, '').inspect}"
        end
      else
        action = @string.get_action(item.to_sym)
        if action.nil? then
          raise ArgumentError, "#{@string} does not have an #{item.inspect} action!"
        end
        @action = action
      end
    end

    @action or raise ArgumentError, "No action given on the command line!"

    # Finally, we can interact with the default option code to build behaviour
    # around the full set of options we now know we support.
    @action.options.each do |option|
      option = @action.get_option(option) # make it the object.
      self.class.option(*option.optparse) # ...and make the CLI parse it.
    end
  end

  def setup
    Puppet::Util::Log.newdestination :console

    # We copy all of the app options to the end of the call; This allows each
    # action to read in the options.  This replaces the older model where we
    # would invoke the action with options set as global state in the
    # interface object.  --daniel 2011-03-28
    @arguments = Array(command_line.args) << options
    validate
  end


  def main
    # Call the method associated with the provided action (e.g., 'find').
    if result = @string.send(@action.name, *arguments)
      puts render(result)
    end
    exit(exit_code)
  end
  def validate
    unless @action
      raise "You must specify #{string.actions.join(", ")} as a verb"
    end
  end
end
