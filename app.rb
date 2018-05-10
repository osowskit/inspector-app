require "sinatra"
require "sinatra/json"
require "octokit"
require "active_support/core_ext/numeric/time"
require 'dotenv'
require "jwt"
Dotenv.load

$stdout.sync = true

CLIENT_ID = ENV.fetch("GITHUB_CLIENT_ID")
CLIENT_SECRET = ENV["GITHUB_CLIENT_SECRET"]
GITHUB_KEY_LOCATION = ENV.fetch("GITHUB_KEY_LOCATION", nil)
if GITHUB_KEY_LOCATION.nil?
  GITHUB_APP_KEY = ENV.fetch("GITHUB_APP_KEY")
else
  info = File.read(GITHUB_KEY_LOCATION)
  GITHUB_APP_KEY = info
end
GITHUB_APP_ID = ENV.fetch("GITHUB_APP_ID")
GITHUB_APP_URL = ENV.fetch("GITHUB_APP_URL")
SESSION_SECRET = ENV.fetch("SESSION_SECRET")

enable :sessions
set :session_secret, SESSION_SECRET
@accept_header = "application/vnd.github.machine-man-preview+json"

# Check whether the user has an access token.
def authenticated?
  true
end

def check_installations
  installation_ids = []
  begin
    response = installations    
    response.each do |installation|
      installation_ids.push(installation.id)
    end

    session[:installation_list] = installation_ids
  rescue => e
    session[:installation_list] = nil
  end
end

def get_jwt
  private_pem = GITHUB_APP_KEY
  private_key = OpenSSL::PKey::RSA.new(private_pem)

  payload = {
    # issued at time
    iat: Time.now.to_i,
    # JWT expiration time (10 minute maximum)
    exp: 5.minutes.from_now.to_i,
    # Integration's GitHub identifier
    iss: GITHUB_APP_ID
  }

  JWT.encode(payload, private_key, "RS256")
end

def set_jwt_client
  begin
    @jwt_client = Octokit::Client.new(:bearer_token => get_jwt, :accept => @accept_header)
  rescue => error
    puts error
  end
end

def get_app_token(installation_id)
  return_token = ''
  begin
    set_jwt_client
    new_token = @jwt_client.create_app_installation_access_token(installation_id, :accept => @accept_header)
    return_token = new_token.token
  rescue => error
    puts error
  end

  return return_token
end


def select_installation!(installation_id)
  session[:selected_installation] = installation_id
end

def installation_selected?
  session[:selected_installation]
end

get "/reset" do 
  session[:selected_installation] = nil
  session[:installation_list] = nil
  redirect "/"
end

def installations
  set_jwt_client
  begin
    results = @jwt_client.find_installations( :accept => @accept_header)
    results
  rescue => e
    puts e
  end
end

# Serve the main page.
get "/" do
  check_installations
  
  erb :index, :locals => {
    :installations => installations, :installation_selected => installation_selected?}
end

# Respond to requests to check a commit. The commit URL is included in the
# url param.
post "/" do  
  # Select an Installation
  puts installation_id = params[:installation_id].to_i
  begin
    result = {repo_list: []}
    
    app_token = get_app_token(installation_id)
    @app_client = Octokit::Client.new(:access_token => app_token)
    response = @app_client.list_app_installation_repositories(:accept => @accept_header)
    
    if response.total_count > 0
      response.repositories.each do |repo|
        return_data = {full_name: repo["full_name"], installation_id: installation_id}
        result[:repo_list].push(return_data)
      end
    end
    
    result[:commit_url] = params[:installation_id]
  rescue => err
    return json :error_message => err
  end
  json result
end

# Ping endpoint for uptime check.
get "/ping" do
  "pong"
end
