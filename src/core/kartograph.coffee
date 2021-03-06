###
    kartograph - a svg mapping library
    Copyright (C) 2011,2012  Gregor Aisch

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
###


class Kartograph

    constructor: (container, width, height) ->
        # instantiates a new map
        me = @
        me.container = cnt = $(container)
        width ?= cnt.width()
        height ?= cnt.height()
        if height == 0
            height = width * .5
        me.viewport = new BBox 0,0,width,height
        me.paper = me.createSVGLayer()
        me.markers = []
        me.pathById = {}
        me.container.addClass 'kartograph'


    createSVGLayer: (id) ->
        me = @
        me._layerCnt ?= 0
        lid = me._layerCnt++
        vp = me.viewport
        cnt = me.container
        paper = Raphael cnt[0],vp.width,vp.height
        svg = $ paper.canvas
        svg.css
            position: 'absolute'
            top: '0px'
            left: '0px'
            'z-index': lid+5

        if cnt.css('position') == 'static'
            cnt.css
                position: 'relative'
                height: vp.height+'px'

        svg.addClass id
        about = $('desc', paper.canvas).text()
        $('desc', paper.canvas).text(about.replace('with ', 'with kartograph '+kartograph.version+' and '))

        paper

    createHTMLLayer: (id) ->
        me = @
        vp = me.viewport
        cnt = me.container
        me._layerCnt ?= 0
        lid = me._layerCnt++
        div = $ '<div class="layer '+id+'" />'
        div.css
            position: 'absolute'
            top: '0px'
            left: '0px'
            width: vp.width+'px'
            height: vp.height+'px'
            'z-index': lid+5
        cnt.append div
        div

    loadMap: (mapurl, callback, opts) ->
        # load svg map
        me = @
        # line 95
        me.clear()
        me.opts = opts ? {}
        me.opts.zoom ?= 1
        me.mapLoadCallback = callback
        me._lastMapUrl = mapurl # store last map url for map cache

        if me.cacheMaps and kartograph.__mapCache[mapurl]?
            # use map from cache
            me._mapLoaded kartograph.__mapCache[mapurl]
        else
            # load map from url
            $.ajax
                url: mapurl
                dataType: "text" # if $.browser.msie then "text" else "xml"
                success: me._mapLoaded
                context: me
                error: (a,b,c) ->
                    warn a,b,c
        return


    _mapLoaded: (xml) ->
        me = @

        if me.cacheMaps
            # cache map svg (as string)
            kartograph.__mapCache ?= {}
            kartograph.__mapCache[me._lastMapUrl] = xml

        try
            xml = $(xml) # if $.browser.msie
        catch err
            warn 'something went horribly wrong while parsing svg'
            return
        me.svgSrc = xml
        vp = me.viewport
        $view = $('view', xml)[0] # use first view
        me.viewAB = AB = kartograph.View.fromXML $view
        padding = me.opts.padding ? 0
        halign = me.opts.halign ? 'center'
        valign = me.opts.valign ? 'center'
        me.viewBC = new kartograph.View AB.asBBox(),vp.width,vp.height, padding, halign, valign
        me.proj = kartograph.Proj.fromXML $('proj', $view)[0]
        me.mapLoadCallback(me)


    addLayer: (src_id, layer_id, path_id) ->
        ###
        add new layer
        ###
        me = @
        me.layerIds ?= []
        me.layers ?= {}

        if __type(src_id) == 'object'
            opts = src_id
            src_id = opts.id
            layer_id = opts.className
            path_id = opts.key
            titles = opts.title
        else
            opts = {}

        layer_id ?= src_id
        svgLayer = $('#'+src_id, me.svgSrc)

        if svgLayer.length == 0
            # warn 'didn\'t find any paths for layer "'+src_id+'"'
            return

        layer = new MapLayer(layer_id, path_id, me, opts.filter)

        $paths = $('*', svgLayer[0])

        for svg_path in $paths
            layer.addPath(svg_path, titles)

        if layer.paths.length > 0
            me.layers[layer_id] = layer
            me.layerIds.push layer_id

        # add event handlers
        checkEvents = ['click']
        for evt in checkEvents
            if __type(opts[evt]) == 'function'
                me.onLayerEvent evt, opts[evt], layer_id
        if opts.tooltip?
            me.tooltips opts.tooltip
        me

    getLayer: (layer_id) ->
        ### returns a map layer ###
        me = @
        if not me.layers[layer_id]?
            warn 'could not find layer ' + layer_id
        me.layers[layer_id]

    getLayerPath: (layer_id, path_id) ->
        me = @
        if me.layers[layer_id]? and me.layers[layer_id].hasPath(path_id)
            return me.layers[layer_id].getPath(path_id)
        null

    onLayerEvent: (event, callback, layerId) ->
        me = @
        me
        layerId ?= me.layerIds[me.layerIds.length-1]

        class EventContext
            constructor: (@type, @cb, @map) ->

            handle: (e) =>
                me = @
                path = me.map.pathById[e.target.getAttribute('id')]
                me.cb path.data

        ctx = new EventContext(event, callback, me)

        if me.layers[layerId]?
            paths = me.layers[layerId].paths
            for path in paths
                $(path.svgPath.node).bind event, ctx.handle


    addMarker: (marker) ->
        me = @
        me.markers.push(marker)
        xy = me.viewBC.project me.viewAB.project me.proj.project marker.lonlat.lon, marker.lonlat.lat
        marker.render(xy[0],xy[1],me.container, me.paper)


    clearMarkers: () ->
        me = @
        for marker in me.markers
            marker.clear()
        me.markers = []


    fadeIn: (opts = {}) ->
        me = @
        layer_id = opts.layer ? me.layerIds[me.layerIds.length-1]
        duration = opts.duration ? 500

        for id, paths of me.layers[layer_id].pathsById
            for path in paths
                if __type(duration) == "function"
                    dur = duration(path.data)
                else
                    dur = duration
                path.svgPath.attr 'opacity',0
                path.svgPath.animate {opacity:1}, dur



    ###
        end of public API
    ###

    loadCoastline: ->
        me = @
        $.ajax
            url: 'coastline.json'
            success: me.renderCoastline
            context: me


    resize: (w, h) ->
        ###
        forces redraw of every layer
        ###
        me = @
        cnt = me.container
        w ?= cnt.width()
        h ?= cnt.height()
        me.viewport = vp = new kartograph.BBox 0,0,w,h
        me.paper.setSize vp.width, vp.height
        vp = me.viewport
        padding = me.opts.padding ? 0
        halign = me.opts.halign ? 'center'
        valign = me.opts.valign ? 'center'
        zoom = me.opts.zoom
        me.viewBC = new kartograph.View me.viewAB.asBBox(),vp.width*zoom,vp.height*zoom, padding,halign,valign
        for id,layer of me.layers
            layer.setView(me.viewBC)

        if me.symbolGroups?
            for sg in me.symbolGroups
                sg.onResize()
        return


    lonlat2xy: (lonlat) ->
        me = @
        lonlat = new kartograph.LonLat(lonlat[0], lonlat[1]) if lonlat.length == 2
        lonlat = new kartograph.LonLat(lonlat[0], lonlat[1], lonlat[2]) if lonlat.length == 3
        a = me.proj.project(lonlat.lon, lonlat.lat, lonlat.alt)
        me.viewBC.project(me.viewAB.project(a))


    showZoomControls: () ->
        me = @
        me.zc = new PanAndZoomControl me
        me

    addSymbolGroup: (symbolgroup) ->
        me = @
        me.symbolGroups ?= []
        me.symbolGroups.push(symbolgroup)


    clear: () ->
        me = @
        if me.layers?
            for id of me.layers
                me.layers[id].remove()
            me.layers = {}
            me.layerIds = []

        if me.symbolGroups?
            for sg in me.symbolGroups
                sg.remove()
            me.symbolGroups = []


    loadStyles: (url, callback) ->
        ###
        loads a stylesheet
        ###
        me = @
        if $.browser.msie
            $.ajax
                url: url
                dataType: 'text'
                success: (resp) ->
                    me.styles = kartograph.parsecss resp
                    callback()
                error: (a,b,c) ->
                    warn 'error while loading '+url, a,b,c

        else
            $('body').append '<link rel="stylesheet" href="'+url+'" />'
            callback()


    applyStyles: (el, className) ->
        ###
        applies pre-loaded css styles to
        raphael elements
        ###
        me = @
        if not me.styles?
            return el

        me._pathTypes ?= ["path", "circle", "rectangle", "ellipse"]
        me._regardStyles ?= ["fill", "stroke", "fill-opacity", "stroke-width", "stroke-opacity"]
        for sel of me.styles
            p = sel
            for selectors in p.split ','
                p = selectors.split ' ' # ignore hierarchy
                p = p[p.length-1]
                p = p.split ':' # check pseudo classes
                if p.length > 1
                    continue
                p = p[0].split '.' # check classes
                classes = p.slice(1)
                if classes.length > 0 and classes.indexOf(className) < 0
                    continue
                p = p[0]
                if me._pathTypes.indexOf(p) >= 0 and p != el.type
                    continue
                # if we made it until here, the styles can be applied
                props = me.styles[sel]
                for k in me._regardStyles
                    if props[k]?
                        el.attr k,props[k]
        el


kartograph.Kartograph = Kartograph

kartograph.map = (container, width, height) ->
    ### short-hand constructor ###
    new Kartograph container, width, height


kartograph.__mapCache = {} # will store svg files

