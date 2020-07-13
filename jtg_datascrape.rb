# currenty, price is only scraping the topline value, not the values for smaller sizes etc.
require 'httparty'
require 'nokogiri'
require 'json'
require 'pry'

count = 1
title_array = []
image_array = []
price_array = []
description_array = []
options_array = []
parse_page = nil
c_parse_page = nil
grab_thumbnails = nil
grab_feature_image = nil
master_array = []
description_followup = nil
description_labels = [
  'Ingredients', 'Format', 'Directions',
  'Format Details', 'Sourcing',
  'Important note about availability of samples',
  'Company history', 'Preparation', 'Note', 'Tip'
]
# Search page loop
26.times do
  page = HTTParty.get("https://justthegoods.net/search?page=#{count}&q=*")

  parse_page = Nokogiri::HTML(page)

  # Item page loop
  parse_page.css('.list-view-items').css('.list-view-item').map do |item|
    product_target = item.css('.product-card').css('.full-width-link')
    c_page = HTTParty.get("https://justthegoods.net#{product_target[0]['href']}")
    c_parse_page = Nokogiri::HTML(c_page)

    c_title = c_parse_page.css('.product-single__title')
    title_array.push(c_title.text)

    c_price = c_parse_page.css('.price-item--regular')
    price_array.push(c_price.text)

    c_description = c_parse_page.css('.product-single__description').to_s
    c_description.gsub!(/\n/, '')
    current_details_array = c_description.split('h4')
    description_hash = {}
    current_details_array.map do |re|
      if re.start_with?('<div class="product-single__description rte">')
        opening_ptag_index = re.index('<p>').nil? ? 0 : re.index('<p>')
        clip_beginning_from_total = re.length - opening_ptag_index

        closing_ptag_index = re.rindex('</p>').nil? ? 0 : re.rindex('</p>')
        clip_ending_amount = re.length - closing_ptag_index
        clipped_total = clip_beginning_from_total - clip_ending_amount
        description_hash[:main_description] =
          re.slice(opening_ptag_index, clipped_total)
            .delete_suffix('<')
            .gsub(/<span>/, '')
            .gsub(%r{</p>}, '')
            .gsub(%r{</span>}, '')
            .gsub(/<br>/, '')
            .gsub(/<p>/, '')
            .gsub(/<div>/, '')
            .gsub(%r{</div>}, '')
            .gsub(/<span style="font-weight: 400;">/, '')
            .gsub(/<li style="font-weight: 400;">/, '')
            .gsub(/<ul>/, ' ')
            .gsub(%r{</ul>}, ' ')
            .gsub(/<li>/, '')
            .gsub(%r{</li>}, ',')
            .strip
      end
      unless description_followup.nil?
        description_hash[description_followup] =
          re.delete_prefix('>')
            .delete_suffix('<')
            .gsub(/<span>/, '')
            .gsub(%r{</p>}, '')
            .gsub(%r{</span>}, '')
            .gsub(/<br>/, '')
            .gsub(/<p>/, '')
            .gsub(/<div>/, '')
            .gsub(%r{</div>}, '')
            .gsub(/<span style="font-weight: 400;">/, '')
            .strip
        description_followup = nil
      end
      description_labels.each do |des|
        if re.include?('>' + des)
          description_followup = des
          break
        end
      end
    end

    description_array.push(description_hash)

    # some products have various options, size of bottle, type of bottle, scent, etc.
    # If any, these details are stored here.
    options_data = {}
    c_simple = c_parse_page.css('.product-single__meta').css('.selector-wrapper')
    c_simple = c_parse_page.css('.product-customizer-option') if c_simple.empty?
    c_simple.each do |sel|
      current_key = sel.search('label').text.gsub(/\n/, '').strip
      options_data[current_key] = []
      sel.search('option').each do |opt|
        current_opt = opt.text.gsub(/\n/, '').strip
        options_data[current_key].push(current_opt)
      end
    end
    options_array.push(options_data)

    imaging_ct = 0 # imaging_ct indexes entries in imaging_data json

    imaging_data = {} # imaging_data is all the images associated with a product

    grab_thumbnails = c_parse_page.css('.product-single__thumbnail-image')

    # Some pages have multiple thumbnail images. Test for this first, bc some pages do not have this
    # tree, while all pages have the `grab_feature_image` tree.
    if !grab_thumbnails.empty?
      grab_thumbnails.map do |imaging|
        datum = {}
        datum['src'] = imaging['src'].strip
        datum['alt'] = imaging['alt'].sub(/Load image into Gallery viewer, /, '').strip
        imaging_data[imaging_ct.to_s] = datum
        imaging_ct += 1
      end
    else
      grab_feature_image = c_parse_page.css('.feature-row__image')
      unless grab_feature_image.empty?
        grab_feature_image.map do |imaging|
          datum = {}
          datum['src'] = imaging['src'].strip
          datum['alt'] = imaging['alt'].sub(/Load image into Gallery viewer, /, '').strip
          imaging_data[imaging_ct.to_s] = datum
          imaging_ct += 1
        end
      end
    end
    image_array.push(imaging_data)
  end

  count += 1
  # END search page loop
end
price_array.each do |p|
  p.gsub!(/[\n \$]/, '')
end
price_array.map!(&:to_f)

max_iterations = [title_array.length, image_array.length, price_array.length].min

ct_master = 0
max_iterations.times do
  profile = {}
  profile['title'] = title_array[ct_master].strip
  profile['image'] = image_array[ct_master]
  profile['price'] = price_array[ct_master]
  profile['description'] = description_array[ct_master]
  profile['options'] = options_array[ct_master]
  master_array.push(profile)
  ct_master += 1
end

File.write('./jtg_data.json', JSON.dump(master_array))
