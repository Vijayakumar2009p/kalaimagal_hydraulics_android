from odoo import api, fields, models
from odoo.exceptions import AccessError

LOCATION_ONLY_GROUP = 'veevee_field_locator.group_location_only'

# Fields the "location only" login may change on existing contacts.
WRITE_ALLOWED = {
    'partner_latitude', 'partner_longitude', 'date_localization',
    'vv_gps_captured', 'vv_gps_accuracy', 'vv_gps_by',
    'street', 'street2', 'city', 'zip', 'state_id', 'country_id',
    'message_main_attachment_id',
    # profile picture chosen from the photos taken in the app
    'image_1920',
}

# Fields it may fill when creating a contact from the app.
CREATE_ALLOWED = WRITE_ALLOWED | {
    'name', 'is_company', 'company_type', 'parent_id', 'type',
    'phone', 'mobile', 'email', 'vat', 'customer_rank', 'lang', 'tz', 'company_id',
}

ADDRESS_FIELDS = ('street', 'street2', 'zip', 'city', 'state_id', 'country_id')


class ResPartner(models.Model):
    _inherit = 'res.partner'

    vv_gps_captured = fields.Boolean(
        string='Location captured on site',
        copy=False,
        help='Latitude/longitude were captured by GPS at the customer site '
             'with the VeeVee Field Locator app.',
    )
    vv_gps_accuracy = fields.Float(string='GPS accuracy (m)', digits=(6, 1), copy=False)
    vv_gps_by = fields.Char(string='Captured by', copy=False)

    def _vv_location_only(self):
        return not self.env.su and self.env.user.has_group(LOCATION_ONLY_GROUP)

    def _vv_refuse(self, extra):
        labels = sorted(self._fields[f].string if f in self._fields else f for f in extra)
        raise AccessError(self.env._(
            'This login can only set customer locations and addresses '
            '(VeeVee Field Locator). Ask the office to change: %(fields)s',
            fields=', '.join(labels),
        ))

    @api.model_create_multi
    def create(self, vals_list):
        if self._vv_location_only():
            for vals in vals_list:
                extra = set(vals) - CREATE_ALLOWED
                if extra:
                    self._vv_refuse(extra)
        return super().create(vals_list)

    def write(self, vals):
        if self._vv_location_only():
            # Contacts created in this same request are left alone: Odoo itself
            # fills a few fields on them (e.g. language from the company).
            now = self.env.cr.now()
            existing = self.filtered(lambda p: p.create_date != now) - self.env.user.partner_id
            extra = set(vals) - WRITE_ALLOWED
            if existing and extra:
                self._vv_refuse(extra)

        vals = dict(vals)
        touches_coords = 'partner_latitude' in vals or 'partner_longitude' in vals
        # Coordinates typed or computed inside Odoo are not GPS captures.
        if touches_coords and 'vv_gps_captured' not in vals:
            vals['vv_gps_captured'] = False

        # base_geolocalize resets latitude/longitude to 0 when only the address
        # changes. Keep pins that were captured on site.
        if any(f in vals for f in ADDRESS_FIELDS) and not touches_coords:
            pinned = self.filtered('vv_gps_captured')
            if pinned:
                for partner in pinned:
                    super(ResPartner, partner).write(dict(
                        vals,
                        partner_latitude=partner.partner_latitude,
                        partner_longitude=partner.partner_longitude,
                    ))
                rest = self - pinned
                return super(ResPartner, rest).write(vals) if rest else True
        return super().write(vals)

    def unlink(self):
        if self._vv_location_only():
            raise AccessError(self.env._(
                'This login cannot delete contacts (VeeVee Field Locator).'))
        return super().unlink()
