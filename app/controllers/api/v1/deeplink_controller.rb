module Api
    module V1
        class DeeplinkController < ApplicationController
            def reset_password
                render html: <<-HTML.html_safe
                <html>
                    <body style="font-family: Arial; text-align:center; padding-top:50px;">
                    <h2>App Not Installed</h2>
                    <p>Please install the WPA app to continue.</p>
                    </body>
                </html>
                HTML
            end
        end
    end
end

