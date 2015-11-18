require 'rubygems'
require 'sinatra'
require 'haml'
require 'logger'
require 'open3'
require 'pp'

configure do
  set :bind, '0.0.0.0'
  set :session_secret, "filtergen"
  enable :sessions
end

helpers do
  def logged_in?
    return !session[:username].nil?
  end

  def protected!
    return if logged_in?
    halt 401, "Not authorised\n"
  end
end

logger = Logger.new(STDOUT)

# Login page
get "/" do
  redirect to("/protected") unless !logged_in?

  haml :index
end

get "/protected" do
  redirect to("/") unless logged_in?

  haml :protected
end
#
# Handle form submission
post "/protected" do
  @error_message = nil
  @error_message = "File not selected" unless logged_in? and params['filterdef']
  @error_message = "File does not have yaml extension" unless File.extname(params['filterdef'][:filename]) == '.yaml'
  @error_message = "File is larger than 5Kb" unless File.size(params['filterdef'][:tempfile]) <= 5120 # 5Kb limit
  
  # Log what we're doing.
  logger.info("Uploaded file from #{request.ip}")

  if @error_message.nil?
    outdir = File.join('uploads', session[:username])
    Dir.mkdir(outdir) unless File.exist?(outdir)
    File.open(File.join(outdir, params['filterdef'][:filename]), "w") do |filterdef|
      filterdef.write(params['filterdef'][:tempfile].read)
    end

    cmdline = "/srv/adminfilter/outputfilter.pl --yaml '" + File.join(outdir, params['filterdef'][:filename]) + "' --out '" + File.join(outdir, 'adminfilters.xml') + "' 2>&1"
    @output, status = Open3.capture2e(cmdline)
    @successful_generation = status.exitstatus == 0

    haml :result
  else
    haml :error
  end
end

get "/download/filters" do
  protected! 
  send_file File.join('uploads', session[:username], 'adminfilters.xml'), :filename => 'filters.xml', :type => 'text/xml'
end

post "/login" do

  # debugging	
  session[:username] = params[:username]
  redirect to("/protected")

  haml :error
end

get "/logout" do
  session[:username] = nil
  redirect to("/")
end
