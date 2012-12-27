class ApplicationController < ActionController::Base
  include UserInfo
#  http_basic_authenticate_with :name => "test", :password => "ttt"

  helper_method :current_user,
                :authentication_check,
                :config_frontend,
                :user_data_full,
                :is_role,
                :model_create_render,
                :model_update_render,
                :model_restory_render,
                :mode_show_rendeder,
                :model_index_render

  before_filter :set_user
  before_filter :cors_preflight_check

  after_filter  :set_access_control_headers
  after_filter  :trigger_events

  # For all responses in this controller, return the CORS access control headers.
  def set_access_control_headers 
    headers['Access-Control-Allow-Origin']      = '*'
    headers['Access-Control-Allow-Methods']     = 'POST, GET, PUT, DELETE, OPTIONS'
    headers['Access-Control-Max-Age']           = '1728000'
    headers['Access-Control-Allow-Headers']     = 'Content-Type, Depth, User-Agent, X-File-Size, X-Requested-With, If-Modified-Since, X-File-Name, Cache-Control'
    headers['Access-Control-Allow-Credentials'] = 'true'
  end

  # If this is a preflight OPTIONS request, then short-circuit the
  # request, return only the necessary headers and return an empty
  # text/plain.

  def cors_preflight_check
    if request.method == 'OPTIONS'
      headers['Access-Control-Allow-Origin']      = '*'
      headers['Access-Control-Allow-Methods']     = 'POST, GET, PUT, DELETE, OPTIONS'
      headers['Access-Control-Allow-Headers']     = 'Content-Type, Depth, User-Agent, X-File-Size, X-Requested-With, If-Modified-Since, X-File-Name, Cache-Control'
      headers['Access-Control-Max-Age']           = '1728000'
      headers['Access-Control-Allow-Credentials'] = 'true'
      render :text => '', :content_type => 'text/plain'
      return false
    end
  end

  private

  # execute events      
  def trigger_events
    Observer::Ticket::Notification.transaction
  end

  # Finds the User with the ID stored in the session with the key
  # :current_user_id This is a common way to handle user login in
  # a Rails application; logging in sets the session value and
  # logging out removes it.
  def current_user
    @_current_user ||= session[:user_id] &&
    User.find_by_id( session[:user_id] )
  end
  def current_user_set(user)
    @_current_user = user
    set_user
  end

  def authentication_check_only
    puts 'authentication_check'
#    puts params.inspect

    # check http basic auth
    authenticate_with_http_basic do |user, password|
      puts 'http basic auth check'
      userdata = User.where( :login => user ).first
      message = ''
      if !userdata
        message = 'authentication failed, user'
      else
        if password != userdata.password
          message = 'authentication failed, pw'
        end
      end

      # return auth ok
      if message == ''

        # remember last login
        userdata.update_last_login

        # set basic auth user to current user
        current_user_set(userdata)
        return {
          :auth => true
        }
      end

      # return auth not ok
      return {
        :auth    => false,
        :message => message,
      }
    end

    # check logon session
    if params['logon_session'] 
      logon_session = ActiveRecord::SessionStore::Session.where( :session_id => params['logon_session'] ).first
      if logon_session
        userdata = User.find( logon_session.data[:user_id] )
      end

      # set logon session user to current user
      current_user_set(userdata)
      return {
        :auth => true
      }
    end

    # return auth not ok (no session exists)
    if !session[:user_id]
      message = 'no valid session, user_id'
      return {
        :auth    => false,
        :message => message,
      }
    end

    return {
      :auth => true
    }
  end

  def authentication_check
    result = authentication_check_only

    # return auth not ok
    if result[:auth] == false
      render(
        :json   => {
          :error => result[:message],
        },
        :status => :unauthorized
      )
      return false
    end

    # return auth ok
    return true
  end

  # Sets the current user into a named Thread location so that it can be accessed
  # by models and observers
  def set_user
    return if !current_user
    UserInfo.current_user_id = current_user.id
  end

  def is_role( role_name )
    return false if !current_user
    return true if current_user.is_role( role_name )
    return false
  end

  def ticket_permission(ticket)
    return true if ticket.permission( :current_user => current_user )

    response_access_deny
    return false
  end

  def is_not_role( role_name )
    return false if is_role( role_name )
    response_access_deny()
    return true
  end

  def response_access_deny
    render(
      :json => {},
      :status => :unauthorized
    )
    return false
  end

  def log_view (object)
    History.log_view( object, current_user )
  end

  def config_frontend
    
    # config
    config = {}
    Setting.select('name').where( :frontend => true ).each { |setting|
      config[setting.name] = Setting.get(setting.name)
    }
    return config
  end

  # model helper
  def model_create_render (object, params)
    begin

      # create object
      generic_object = object.new( object.param_cleanup(params) )

      # set created_by_id and updated_by_id
      generic_object.created_by_id = current_user.id
      generic_object.updated_by_id = current_user.id

      # save object
      generic_object.save
      model_create_render_item(generic_object)
    rescue Exception => e
      logger.error e.message
      render :json => { :error => e.message }, :status => :unprocessable_entity
    end
  end
  def model_create_render_item (generic_object)
    render :json => generic_object, :status => :created
  end

  def model_update_render (object, params)
    begin

      # find object
      generic_object = object.find( params[:id] )

      # set created_by_id and updated_by_id
      params['updated_by_id'] = current_user.id

      # save object
      generic_object.update_attributes( object.param_cleanup(params) )
      model_update_render_item(generic_object)
    rescue Exception => e  
      logger.error e.message
      render :json => { :error => e.message }, :status => :unprocessable_entity
    end
  end
  def model_update_render_item (generic_object)
    render :json => generic_object, :status => :ok
  end

  def model_destory_render (object, params)
    begin
      generic_object = object.find( params[:id] )
      generic_object.destroy
      model_destory_render_item()
    rescue Exception => e
      logger.error e.message
      render :json => { :error => e.message }, :status => :unprocessable_entity
    end
  end
  def model_destory_render_item ()
    render :json => {}, :status => :ok
  end

  def model_show_render (object, params)
    begin
      generic_object = object.find( params[:id] )
      model_show_render_item(generic_object)
    rescue Exception => e
      logger.error e.message
      render :json => { :error => e.message }, :status => :unprocessable_entity
    end
  end
  def model_show_render_item (generic_object)
    render :json => generic_object, :status => :ok
  end

  def model_index_render (object, params)
    begin
      generic_object = object.all
      model_index_render_result( generic_object )
    rescue Exception => e
      logger.error e.message
      render :json => { :error => e.message }, :status => :unprocessable_entity
    end
  end
  def model_index_render_result (generic_objects)
    render :json => generic_objects, :status => :ok
  end

end
