from odoo import api, models


class VeeveeFieldLocator(models.AbstractModel):
    _name = 'veevee.field.locator'
    _description = 'VeeVee Field Locator app support'

    @api.model
    def get_app_info(self):
        """Called by the app after login to offer APK updates.

        Set in Settings > Technical > System Parameters:
          veevee_field_locator.latest_version  e.g. 1.1.0
          veevee_field_locator.apk_url         link to download the new APK
          veevee_field_locator.release_notes   optional short text
        """
        params = self.env['ir.config_parameter'].sudo()
        return {
            'latest_version': params.get_param('veevee_field_locator.latest_version', '1.0.0'),
            'apk_url': params.get_param('veevee_field_locator.apk_url', ''),
            'release_notes': params.get_param('veevee_field_locator.release_notes', ''),
        }
