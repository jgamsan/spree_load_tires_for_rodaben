# encoding: UTF-8
require 'csv'

class ImportTiresFromEurotyre
  def initialize()
    @agent = Mechanize.new
    @final = "#{Rails.root}/vendor/products/listado-neumaticos-eurotyre.csv"
    @send_file = "#{Rails.root}/vendor/products/listado-neumaticos-no-incorporados-eurotyre.csv"
    @image_wd = "#{Rails.root}/vendor/products/images/"
    @default_wd = "#{Rails.root}/app/assets/images/"
    @default_img = "default.png"
    @total = []
    @no_leidos = []
    @horario = []
    @created = 0
    @updated = 0
    @deleted = 0
    @readed = 0
    @widths = Spree::TireWidth.all.map {|x| x.name}
    @series = Spree::TireSerial.all.map {|x| x.name}
    @llantas = Spree::TireInnertube.all.map {|x| x.name}
    @vel = Spree::TireSpeedCode.all.map {|x| x.name}
    @marcas_eurotyre = CSV.read("#{Rails.root}/vendor/products/listado-marcas-eurotyre.csv").flatten
    I18n.locale = 'es'
  end

  def run
    if login
      read_from_eurotyre(login)
      export_to_csv
      load_from_csv
      delete_no_updated
      send_mail
    end
  end

  def login
    username = 'nrodaben@yahoo.es'
    password = 'jose1222'
    direccion = 'http://www.eurotyre.pt/shop/login'
    page = @agent.get(direccion)
    etyre_form = page.form('login')
    etyre_form.username = login
    etyre_form.passwd = password
    etyre_form.submit
  end

  def read_from_eurotyre(page)
    ruedas = []
    form = page.form('search')
    select_list = form.field_with(:name => "u_marca")
    @marcas_eurotyre.each do |marca|
      select_list.value = [marca]
      page2 = form.submit
      #puts marca
      page2.search(".//table[@id='product_list']//tbody//tr").each do |d|
        for i in 0..9
          ruedas << d.search(".//td")[i].text
        end
      end
      for i in 0..(ruedas.count/10) - 1
        @total << [ruedas[i*10], ruedas[i*10 + 1], ruedas[i*10 + 2],
                  ruedas[i*10 + 3], ruedas[i*10 + 4], ruedas[i*10 + 5],
                  ruedas[i*10 + 6], ruedas[i*10 + 7], ruedas[i*10 + 8]]
        @readed += 1
      end
      ruedas.clear
    end
  end

  def export_to_csv
    CSV.open(@final, "wb") do |row|
      @total.each do |element|
        #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, stock]
        row << element
      end
    end
  end

  def load_from_csv
    #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, stock]
    result = []
    fallos = []
    no_leidos = []
    i = j = 0
    hoy = Date.today
    productos = Spree::Product.where(:supplier_id => 2).map {|x| x.name}.flatten
    CSV.foreach(@final) do |row|
      begin
        if productos.include?(row[6]) # producto existe
          articulo = Spree::Product.find_by_name(row[6])
          articulo.update_column(:show_in_offert, row[7].to_f > 0 ? true : false)
          variante = Spree::Variant.find_by_product_id(articulo.id)
          variante.update_attributes(
              :count_on_hand => set_stock(row[9]),
              :cost_price => row[7],
              :price => row[8] * 1.05,
              :price_in_offert => row[7] * 1.05 #falta de poner el precio de venta segun cliente
          )
          @updated += 1
                                      # actualizar los precios
        else
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[6]
          product.permalink = row[6].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = hoy.strftime("%y%m%d%H%m") + i.to_s
          product.available_on = hoy - 1.day
          product.price = row[8] * 1.05 #falta de poner el precio de venta segun cliente
          product.cost_price = row[7]
          product.price_in_offert = row[7] * 1.05
          product.show_in_offert = row[7].to_f > 0 ? true : false
          product.tire_width_id = set_width(row)
          product.tire_serial_id = set_serial(row)
          product.tire_innertube_id = set_innertube(row)
          product.tire_speed_code_id = set_speed_code(row)
          product.tire_rf = false
          product.tire_gr = false
          product.tire_season = 2
          product.taxons << Spree::Taxon.find(6) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(row)) #cargar marca
          if product.save!
            #puts "Creado articulo #{row[0]}"
            j += 1
          end
          v = Spree::Variant.find_by_product_id(product.id)
          v.update_column(:count_on_hand, row[9])
          add_image(product, @default_wd, @default_img)
          v = nil
          product = nil
          @created += 1
        end
      rescue Exception => e
        #puts e
        fallos << [row[0], e]
        no_leidos << [row[0], row[1], row[2], row[3], row[4], row[5]]
        next
      end
    end
    unless fallos.empty?
      CSV.open("#{Rails.root}/vendor/products/listado-fallos-eurotyre.csv", "wb") do |row|
        fallos.each do |element|
          row << element
        end
      end
    end
    unless no_leidos.empty?
      headers_row = ["Ancho", "Perfil", "Llanta", "IC", "IV", "Marca", "Modelo", "Oferta", "Precio", "Stock"]
      CSV.open(@send_file, "wb", {headers: headers_row, write_headers: true}) do |row|
        no_leidos.each do |element|
          row << element
        end
      end
    end
  end

  def set_width(row)
    #[ancho, perfil, llanta, ic, iv, marca, modelo, oferta, precio, stock]
    ancho = row[0]
    ancho == nil ? ancho : @widths.index(ancho) + 1
  end

  def set_serial(row)
    serie = row[1]
    serie == nil ? serie : @series.index(serie) + 1
  end

  def set_innertube(row)
    llanta = row[2]
    llanta == nil ? llanta : @llantas.index(llanta) + 1
  end

  def set_speed_code(row)
    vel = row[4]
    vel == nil ? vel : @vel.index(vel) + 1
  end

  def set_brand(row)
    marca = row[5].titleize
    Spree::Taxon.find_by_name(:name => marca).id
  end

  def delete_no_updated

  end

  def send_mail
    begin
      Spree::NotifyMailer.report_notification(@readed, @updated, @deleted, @created).deliver
    rescue Exception => e
      logger.error("#{e.class.name}: #{e.message}")
      logger.error(e.backtrace * "\n")
    end
  end
end
