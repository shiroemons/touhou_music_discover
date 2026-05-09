# frozen_string_literal: true

module Admin
  module IconsHelper
    ICON_PATHS = {
      arrow_down_circle: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M8 12l4 4 4-4', 'M12 8v8'],
      arrow_left: ['M19 12H5', 'M12 19l-7-7 7-7'],
      box_arrow_up_right: ['M7 7h10v10', 'M7 17 17 7', 'M6 5H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-2'],
      check: ['M20 6 9 17l-5-5'],
      check_circle: ['M20 6 9 17l-5-5', 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z'],
      chevron_double_left: ['M11 17 6 12l5-5', 'M18 17l-5-5 5-5'],
      chevron_double_right: ['M13 17l5-5-5-5', 'M6 17l5-5-5-5'],
      chevron_left: ['M15 18l-6-6 6-6'],
      chevron_right: ['M9 18l6-6-6-6'],
      collection: ['M4 6h16', 'M4 12h16', 'M4 18h16'],
      dashboard: ['M4 13a8 8 0 1 1 16 0', 'M12 13l4-4', 'M5 19h14'],
      download: ['M12 3v12', 'M7 10l5 5 5-5', 'M5 21h14'],
      edit: ['M12 20h9', 'M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z'],
      error_circle: ['M12 8v5', 'M12 16h.01', 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z'],
      eye: ['M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z', 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z'],
      lightning: ['M13 2 4 14h7l-1 8 10-14h-7l1-6Z'],
      list: ['M8 6h13', 'M8 12h13', 'M8 18h13', 'M3 6h.01', 'M3 12h.01', 'M3 18h.01'],
      list_ordered: ['M10 6h11', 'M10 12h11', 'M10 18h11', 'M4 6h1v4', 'M4 16h2v2H4l2-4H4'],
      play: ['M8 5v14l11-7Z'],
      plus: ['M12 5v14', 'M5 12h14'],
      search: ['M21 21l-4.35-4.35', 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Z'],
      service: ['M12 4v16', 'M8 8h8', 'M8 16h8'],
      trash: ['M3 6h18', 'M8 6V4h8v2', 'M6 6l1 16h10l1-16'],
      warning: ['M12 9v4', 'M12 17h.01', 'M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z'],
      x: ['M18 6 6 18', 'M6 6l12 12']
    }.freeze

    def admin_icon(name, label: nil)
      paths = ICON_PATHS.fetch(name.to_sym)

      tag.svg(
        safe_join(paths.map { |path| tag.path(d: path) }),
        class: 'admin-icon',
        viewBox: '0 0 24 24',
        fill: 'none',
        stroke: 'currentColor',
        stroke_width: 2,
        stroke_linecap: 'round',
        stroke_linejoin: 'round',
        aria: { hidden: label.blank?, label: label.presence },
        role: label.present? ? 'img' : nil
      )
    end
  end
end
