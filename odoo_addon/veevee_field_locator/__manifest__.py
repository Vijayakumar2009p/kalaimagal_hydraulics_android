{
    'name': 'VeeVee Field Locator',
    'version': '19.0.1.1.0',
    'category': 'Sales/CRM',
    'summary': 'Support module for the VeeVee Field Locator Android app (GPS-pinned contacts)',
    'description': """
Support module for the VeeVee Field Locator Android app.

* Hides the geolocation "Refresh" / "Compute based on address" buttons for
  everyone except Settings administrators, so GPS pins captured on site are
  not replaced by a rough address-based estimate.
* Keeps GPS pins when only the address of the contact is edited
  (standard Odoo resets latitude/longitude to 0 in that case).
* Adds the "Field Locator: location only" group for the shared app login:
  it can set locations and addresses and create contacts with basic details,
  but cannot change other details or delete contacts.
* Tells the app when a newer APK is available (System Parameters).
* Adds the "Field Visit" activity type: schedule it on a contact for a
  field staff user; the app lists it and marks it done on site with GPS.
""",
    'author': 'VeeVee Infotech',
    'website': 'https://www.veeveeinfotech.com',
    'license': 'LGPL-3',
    'depends': ['base_geolocalize', 'mail'],
    'data': [
        'security/security.xml',
        'data/ir_config_parameter.xml',
        'data/mail_activity_type.xml',
        'views/res_partner_views.xml',
    ],
    'installable': True,
    'application': False,
}
