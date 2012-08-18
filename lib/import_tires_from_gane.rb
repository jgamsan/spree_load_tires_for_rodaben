# encoding: UTF-8
require 'csv'

class ImportTiresFromGane

  def initialize()
    @agent = Mechanize.new
    @final = "#{Rails.root}/vendor/products/listado-neumaticos.csv"
    @send_file = "#{Rails.root}/vendor/products/listado-neumaticos-no-incorporados.csv"
    @total = []
    @no_leidos = []
    @horario = []
    @created = 0
    @updated = 0
    @deleted = 0
    @readed = 0
    @tubes = %w(TL TT RU)
    @widths = Spree::TireWidth.all.map {|x| x.name}
    @series = Spree::TireSerial.all.map {|x| x.name}
    @llantas = Spree::TireInnertube.all.map {|x| x.name}
    @vel = Spree::TireSpeedCode.all.map {|x| x.name}
    t = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| [x.name.upcase, x.id]}.flatten
    @marcas = Spree::Taxon.where(:parent_id => 2).order("id").map {|x| x.name.upcase}
    @taxons = Hash[*t]
    @error = ""
    @modificaciones = %w(GOODYEAR)
    I18n.locale = 'es'
  end

  def run
    #if login
     # read_from_gane
      #export_to_csv
      #load_from_csv
      #delete_no_updated
      send_mail
    end
  end

  def read_from_gane
    str = "http://galaicoasturianadeneumaticos.distritok.com/sqlcommerce/disenos/plantilla1/seccion/Catalogo.jsp?idIdioma=&idTienda=50&cPath=61"
    sch = ".//table[@class='result']//tr//td[@class='result_right']//a[@title='Siguiente ']"
    links = []
    until str.empty?
      page = @agent.get(str)
      page.search(".//table[@class='tableBox_output']//tr").each do |d|
        t = d.search("td[@width='900']//a").text.strip
        r = d.search("td//span[@class='linCat']").map {|x| x.text}
        unless r.empty?
          if r[1] == "Consultar"
              p = k = pf = s = 0
          else
            s = r[0].to_s.strip
            p = r[1].to_s.delete("€").strip.gsub(/,/, '.').to_f
            k = r[2].to_s.delete("%").strip.gsub(/,/, '.').to_f
            pf = r[3].to_s.delete("€").strip.gsub(/,/, '.').to_f
            #puts "Stock es #{p}. PVP final es #{pf}"
          end
          @total << [t, s, p, k, pf]
          @readed += 1
        end
      end
      links.clear
      page.search(sch).each do |link|
        links << link[:href]
      end
      links = links.uniq
      str = links[0].to_s
      #puts str
    end
  end

  def export_to_csv
    CSV.open(@final, "wb") do |row|
      @total.each do |element|
        #[nombre, stock, precio, descuento, precio final]
        row << element
      end
    end
  end

  def load_from_csv
    # [ancho, serie, llanta, vel, tube, marca, gr]
    result = []
    fallos = []
    no_leidos = []
    i = j =0
    hoy = Date.today
    productos = Spree::Product.find_by_sql("Select name from spree_products;").map {|x| x.name}.flatten
    CSV.foreach(@final) do |row|
      begin
        unless row[0].blank?
          if productos.include?(row[0]) # producto existe
            articulo = Spree::Product.find_by_name(row[0])
            variante = Spree::Variant.find_by_product_id(articulo.id)
            variante.update_attributes(
              :count_on_hand => set_stock(row[1]),
              :cost_price => row[4],
              :price => row[4] * 1.05 #falta de poner el precio de venta segun cliente
            )
            @updated += 1
            # actualizar los precios
          else
            result = read_format(row[0])
            i += 1
            # crear uno nuevo
            product = Spree::Product.new
            product.name = row[0]
            product.permalink = row[0].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
            product.sku = hoy.year.to_s + hoy.month.to_s + hoy.day.to_s + "-" + i.to_s
            product.available_on = hoy - 1.day
            #product.count_on_hand = set_stock(row[1])
            product.price = row[4] * 1.05 #falta de poner el precio de venta segun cliente
            product.cost_price = row[4]
            product.tire_width_id = set_width(result)
            product.tire_serial_id = set_serial(result)
            product.tire_innertube_id = set_innertube(result)
            product.tire_speed_code_id = set_speed_code(result)
            product.tire_rf = false
            product.tire_gr = result[6]
            product.tire_season = set_season(result)
            product.taxons << Spree::Taxon.find(set_catalog) #cargar categoria
            product.taxons << Spree::Taxon.find(set_brand(result)) #cargar marca
            if product.save!
              #puts "Creado articulo #{row[0]}"
              j += 1
            end
            v = Spree::Variant.find_by_product_id(product.id)
            v.update_column(:count_on_hand, set_stock(row[1]))
            v = nil
            product = nil
            @created += 1
          end
        end
      rescue Exception => e
        #puts e
        fallos << [row[0], e]
        no_leidos << [row[0], row[1], row[2], row[3], row[4]]
        next
      end
    end
    unless fallos.empty?
      CSV.open("#{Rails.root}/vendor/products/listado-fallos.csv", "wb") do |row|
        fallos.each do |element|
          row << element
        end
      end
    end
    unless no_leidos.empty?
      headers_row = ["Nombre", "Stock", "Precio", "Descuento", "Precio Final"]
      CSV.open(@send_file, "wb", {headers: headers_row, write_headers: true}) do |row|
        no_leidos.each do |element|
          row << element
        end
      end
    end
  end

  def delete_no_updated
    nuevos = []
    total = Spree::Product.all
    almacenados = total.map {|x| x.name}
    CSV.foreach(@final) do |row|
      nuevos << row[0]
    end
    eliminar = almacenados - nuevos
    eliminar.each do |element|
      t = Spree::Product.find_by_name(element)
      unless t.nil?
        t.destroy
        @deleted += 1
      end
    end
  end

  def send_mail
    begin
      Spree::NotifyMailer.report_notification(@readed, @updated, @deleted, @created).deliver
    rescue Exception => e
      logger.error("#{e.class.name}: #{e.message}")
      logger.error(e.backtrace * "\n")
    end
  end

  private

  def login
    login = '929'
    password = 'B36973667'
    direccion = 'http://galaicoasturianadeneumaticos.distritok.com/'
    page = @agent.get(direccion)
    gane_form = page.form('login')
    gane_form.login = login
    gane_form.password = password
    gane_form.submit
  end

  def read_format(rueda)
    rueda = rueda.to_s
    if rueda =~ %r{(\S+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)([TLRU]{2})(?:\s|:)(\S+)(?:\s|:)} #1
      g = [$1,$2,$3,$4,$5,$6]
      if g[0] =~ %r{(\d+)(?:/|:)(\d+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[0]
        serie = ancho_nuevo[1]
      elsif g[0] =~ %r{(\d+)(?:[Xx]|:)(\S+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[1]
      else
        ancho = g[0]
        serie = nil
      end
      llanta = g[2].scan(/\d+/)[0]
      tube = read_tube(g[3])
      vel = g[4]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\S+)(?:\s|:)([TLRU]{2})(?:\s|:)} #3
      g = [$1,$2,$3,$4]
      if g[0] =~ %r{(\S+)(?:/|:)(\S+)(?:-|:)(\S+)}
        ancho_nuevo = [$1,$2,$3]
        if ancho_nuevo[0].to_i > 100
          ancho = ancho_nuevo[0]
          serie = ancho_nuevo[1]
          llanta = ancho_nuevo[2].scan(/\d+/)[0]
        else
          ancho = ancho_nuevo[1]
          llanta = ancho_nuevo[2].scan(/\d+/)[0]
          serie = nil
        end
      elsif g[0] =~ %r{(\S+)(?:-|:)(\S+)}
        h = [$1,$2]
        ancho = h[0]
        serie = nil
      end
      tube = g[1]
      vel = nil
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, true]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)(\S+)(?:/|:)(\S+)} #11
      g = [$1,$2,$3,$4]
      if g[0] =~ %r{(\d+)(?:/|:)(\d+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[0]
        serie = ancho_nuevo[1]
      else
        ancho = g[0]
        serie = nil
      end
      llanta = g[2].scan(/\d+/)[0]
      tube = nil
      vel = g[3]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:\s|:)(\D)(?:\s|:)(\d+[A-Z])(?:\s|:)([TLRU]{2})(?:\s|:)(\S+)(?:\s|:)(\S+)} #13
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = g[3]
      vel = g[5]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\S+)(?:\s|:)(\S+)(?:\s|:)(\S+)} #4
      g = [$1,$2,$3]
      if g[0] =~ %r{(\S+)(?:/|:)(\S+)(?:-|:)(\S+)}
        ancho_nuevo = [$1,$2,$3]
        if ancho_nuevo[0].to_i > 100
          ancho = ancho_nuevo[0]
          serie = ancho_nuevo[1]
          llanta = ancho_nuevo[2]
        else
          ancho = ancho_nuevo[1]
          llanta = ancho_nuevo[2]
          serie = nil
        end
      elsif g[0] =~ %r{(\d+)(?:[Xx]|:)(\d+)}
        ancho_nuevo = [$1,$2]
        ancho = ancho_nuevo[1]
        serie = nil
        llanta = nil
      elsif g[0] =~ %r{(\S+)(?:-|:)(\S+)}
        h = [$1,$2]
        ancho = h[0]
        serie = nil
      end
      vel = nil
      if g[1].include?("PR")
        vel = nil
      else
        vel = g[1]
      end
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    else
      puts "No leido #{rueda}"
    end
  end

  def read_taxon(rueda)
   str = rueda.split
   if str.include?("GOODYEAR") || (str.include?("GOOD") & str.include?("YEAR"))
    inter = ["GOOD YEAR"]
   else
    inter = str & @marcas
   end

   @taxons.fetch(inter[0])
   #@marcas.find_index(inter[0])

  end

  def read_tube(tube)
    if tube.nil?
      nil
    else
      @tubes.find_index(tube)
    end
  end

  def set_width(row)
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
    str = row[3]
    if str.nil?
      vel = nil
    else
      if str =~ %r{(\S+)(?:/|:)(\S+)}
        vel_nueva = [$1,$2]
        vel = get_vel_code(vel_nueva[1])
      elsif str == "ZR"
        vel = str
      else
        vel = get_vel_code(str)
      end
    end
    vel == nil ? vel : @vel.index(vel) + 1
  end

  def set_season(row)
    3
  end

  def set_brand(row)
    marca = row[5]
  end

  def set_stock(stock)
    if stock.include?("<")
      stock.delete("<").scan(/\d+/)[0].to_i - 1
    elsif stock.include?(">")
      stock.delete(">").scan(/\d+/)[0].to_i
    else
      stock.to_i
    end
  end

  def set_catalog
    3
  end

  def get_vel_code(str)
    if str.include?("A")
      str.scan(/[A]\d/)[0]
    else
      str.scan(/[A-Z]/)[0]
    end
  end

  def read_image(links)
    links.each do |ln|
      page1 = agent.get(ln).search(".//table[@id='tablaFotograf']//tr")
      page1.each do |m|
        l1 = m.search("td//img[@id='imagenProducto']").map {|x| x[:src]}
        puts l1
        b = l1[0]
        d = File.basename(b)
        unless d == "0_articulosinfoto.jpg"
          Net::HTTP.start("galaicoasturianadeneumaticos.distritok.com") { |http|
            resp = http.get(b)
            open(d, "wb") { |file|
              file.write(resp.body)
            }
          }
        end
      end
    end
  end

  def save_image

  end

end
