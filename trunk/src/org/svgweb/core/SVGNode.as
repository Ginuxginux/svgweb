/*
 Copyright (c) 2009 by contributors:

 * James Hight (http://labs.zavoo.com/)
 * Richard R. Masters
 * Google Inc. (Brad Neuberg -- http://codinginparadise.org)

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

package org.svgweb.core
{
    import org.svgweb.core.SVGViewer;
    import org.svgweb.nodes.*;
    import org.svgweb.utils.SVGColors;
    import org.svgweb.utils.SVGUnits;
    
    import flash.display.CapsStyle;
    import flash.display.DisplayObject;
    import flash.display.JointStyle;
    import flash.display.LineScaleMode;
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.geom.Matrix;
    import flash.utils.getDefinitionByName;
    import flash.utils.getQualifiedClassName;

    /** Base node extended by all other SVG Nodes **/
    public class SVGNode extends Sprite
    {
        public static const ATTRIBUTES_NOT_INHERITED:Array = ['id', 'x', 'y', 'width', 'height', 'rotate', 'transform', 
                                                'gradientTransform', 'opacity', 'mask', 'clip-path', 'href', 'target', 'viewBox'];
        
        public namespace xlink = 'http://www.w3.org/1999/xlink';
        public namespace svg = 'http://www.w3.org/2000/svg';
        public namespace aaa = 'http://www.w3.org/XML/1998/namespace';
       
        public var svgRoot:SVGSVGNode = null;
        public var isMask:Boolean = false;

        //Used for gradients
        public var xMin:Number;
        public var xMax:Number;
        public var yMin:Number;
        public var yMax:Number;

        protected var _parsedChildren:Boolean = false;
        public var _initialRenderDone:Boolean = false;

        protected var _firstX:Boolean = true;
        protected var _firstY:Boolean = true;

        protected var _xml:XML;
        protected var _invalidDisplay:Boolean = false;
        protected var _id:String = null;
        protected var _graphicsCommands:Array;
        protected var _styles:Object;

        protected var original:SVGNode;
        protected var _isClone:Boolean = false;
        protected var _clones:Array = new Array();
        
        protected var animations:Array = new Array();
        
        /**
         *
         * To handle certain flash quirks, and to support certain SVG features,
         * the implementation of one SVG node is split into one to four
         * Sprites which perform the functions of transforming, clipping, and drawing.
         * Here are the specific functions performed by each sprite:
         *
         * transformSprite:
         *      * handles the transform attribute
         *      * is the parent of the clip-path mask
         *      * has mask set to 'default' mask (top level bounding box)
         *
         * clipSprite:
         *      * has mask set to 'clip-path' mask
         *
         * drawSprite:
         *      * handles all graphics access
         *      * handles x,y,rotate,opacity attributes
         *      * eventListeners added here
         *      * filters added here
         *
         * viewBoxSprite:
         *      * handles viewBox transform
         *      * parent of SVG children
         *
         */
        public var transformSprite:Sprite;
        public var clipSprite:Sprite;
        public var drawSprite:Sprite;
        public var viewBoxSprite:Sprite;

        /**
         * Constructor
         *
         * @param xml XML object containing the SVG document. @default null
         *
         * @return void.
         */
        public function SVGNode(svgRoot:SVGSVGNode, xml:XML = null, original:SVGNode = null):void {
            this.svgRoot = svgRoot;

            transformSprite = this;

            // This handles strange gradient bugs with negative transforms
            // by separating the transform from the drawing object.
            clipSprite = new Sprite();
            transformSprite.addChild(clipSprite);

            // In case the object has a gaussian filter, flash will blur the object mask,
            // even if the mask is not drawn with a blur. This is not correct rendering.
            // So, we use a stub parent object to hold the mask, in order to isolate the
            // mask from the filter. A child is created for drawing and the
            // filter is applied to the child.
            drawSprite = new Sprite();
            clipSprite.addChild(drawSprite);

            // In case the object has a viewBox, the resulting transform should only apply
            // to the children of the object, so create a child sprite to hold the transform.
            viewBoxSprite = new Sprite();
            drawSprite.addChild(viewBoxSprite);

            this.xml = xml;
            if (original) {
                this.original = original;
                this._isClone = true;
            }

            drawSprite.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            this.addEventListener(Event.REMOVED_FROM_STAGE, onRemovedFromStage);
        }

        /**
         * Parse the SVG XML.
         * This handles creation of child nodes.
         **/
        protected function parseChildren():void {
            var text:String = '';
            for each (var childXML:XML in this._xml.children()) {
                if (childXML.nodeKind() == 'element') {
                    // If we support text values then set them
                    if (this.hasText()) {
                        if (childXML.localName() == '__text'
                            && childXML.children().length() > 0) {
                            // for the SVGViewerWeb we use a nested
                            // SVGDOMTextNode to store the actual value; this
                            // class is necessary so that we can do text
                            // node detection in the browser and have a unique
                            // GUID per DOM text node
                            text += childXML.children().toString();
                        }
                    }

                    var newChildNode:SVGNode = this.parseNode(childXML);
                    if (!newChildNode) {
                        continue;
                    }
                    SVGNode.addSVGChild(viewBoxSprite, newChildNode);
                } else if (childXML.nodeKind() == 'text'
                           && this.hasText()) {
                    text = this._xml.text().toString();
                }  
            }
            
            if (this.hasText()) {
                this.setText(text);
            }
        }

        public function parseNode(childXML:XML):SVGNode {
            var childNode:SVGNode = null;
            var nodeName:String = childXML.localName();                    
            nodeName = nodeName.toLowerCase();
            switch(nodeName) {
                case "a":
                    childNode = new SVGANode(this.svgRoot, childXML);
                    break;
                case "animate":
                    childNode = new SVGAnimateNode(this.svgRoot, childXML);
                    break;    
                case "animatemotion":
                    childNode = new SVGAnimateMotionNode(this.svgRoot, childXML);
                    break;    
                case "animatecolor":
                    childNode = new SVGAnimateColorNode(this.svgRoot, childXML);
                    break;    
                case "animatetransform":
                    childNode = new SVGAnimateTransformNode(this.svgRoot, childXML);
                    break;    
                case "audio":
                    childNode = new SVGAudioNode(this.svgRoot, childXML);
                    break;
                case "circle":
                    childNode = new SVGCircleNode(this.svgRoot, childXML);
                    break;        
                case "clippath":
                    childNode = new SVGClipPathNode(this.svgRoot, childXML);
                    break;
                case "desc":
                    childNode = new SVGDescNode(this.svgRoot, childXML);
                    break;
                case "defs":
                    childNode = new SVGDefsNode(this.svgRoot, childXML);
                    break;
                case "ellipse":
                    childNode = new SVGEllipseNode(this.svgRoot, childXML);
                    break;
                case "filter":
                    childNode = new SVGFilterNode(this.svgRoot, childXML);
                    break;
                case "font":
                    childNode = new SVGFontNode(this.svgRoot, childXML);
                    break;
                case "font-face":
                    childNode = new SVGFontFaceNode(this.svgRoot, childXML);
                    break;
                case "g":                        
                    childNode = new SVGGroupNode(this.svgRoot, childXML);
                    break;
                case "glyph":                        
                    childNode = new SVGGlyphNode(this.svgRoot, childXML);
                    break;
                case "image":                        
                    childNode = new SVGImageNode(this.svgRoot, childXML);
                    break;
                case "line": 
                    childNode = new SVGLineNode(this.svgRoot, childXML);
                    break;    
                case "lineargradient": 
                    childNode = new SVGLinearGradient(this.svgRoot, childXML);
                    break;    
                case "mask":
                    childNode = new SVGMaskNode(this.svgRoot, childXML);
                    break;                        
                case "metadata":
                    childNode = new SVGMetadataNode(this.svgRoot, childXML);
                    break;
                case "missing-glyph":                        
                    childNode = new SVGMissingGlyphNode(this.svgRoot, childXML);
                    break;
                case "pattern":
                    childNode = new SVGPatternNode(this.svgRoot, childXML);
                    break;
                case "polygon":
                    childNode = new SVGPolygonNode(this.svgRoot, childXML);
                    break;
                case "polyline":
                    childNode = new SVGPolylineNode(this.svgRoot, childXML);
                    break;
                case "path":                        
                    childNode = new SVGPathNode(this.svgRoot, childXML);
                    break;
                case "radialgradient": 
                    childNode = new SVGRadialGradient(this.svgRoot, childXML);
                    break;    
                case "rect":
                    childNode = new SVGRectNode(this.svgRoot, childXML);
                    break;
                case "script":
                    childNode = new SVGScriptNode(this.svgRoot, childXML);
                    break;
                case "set":
                    childNode = new SVGSetNode(this.svgRoot, childXML);
                    break;
                case "stop":
                    childNode = new SVGStopNode(this.svgRoot, childXML);            
                    break;
                case "svg":
                    childNode = new SVGSVGNode(this.svgRoot, childXML, this.svgRoot.viewer);
                    break;                        
                case "symbol":
                    childNode = new SVGSymbolNode(this.svgRoot, childXML);
                    break;                        
                case "text":    
                    childNode = new SVGTextNode(this.svgRoot, childXML);
                    break; 
                case "title":    
                    childNode = new SVGTitleNode(this.svgRoot, childXML);
                    break; 
                case "tspan":                        
                    childNode = new SVGTspanNode(this.svgRoot, childXML);
                    break; 
                case "use":
                    childNode = new SVGUseNode(this.svgRoot, childXML);
                    break;
                case "video":
                    childNode = new SVGVideoNode(this.svgRoot, childXML);
                    break;
                case "__text":
                    /** These are fake text nodes necessary for integration
                        with the browser through JavaScript. */
                    childNode = new SVGDOMTextNode(this.svgRoot, childXML);
                    break;
                case "null":
                    break;
                    
                default:
                    trace("Unknown Element: " + nodeName);
                    childNode = new SVGUnknownNode(this.svgRoot, childXML);
                    break;    
            }
            return childNode;
        }
        
        /**
         * Called when a node is created after page load with XML content
         * added as a child. Forces a parse.
         */
        public function forceParse():void {
            if (this._xml != null && !this._parsedChildren) {
                this.parseChildren();
                for (var i:uint = 0; i < viewBoxSprite.numChildren; i++) {
                    var child:DisplayObject = viewBoxSprite.getChildAt(i);
                    if (child is SVGNode) {
                        SVGNode(child).forceParse();
                    }
                }
                
                this._parsedChildren = true;
            } 
        }

        /**
         * Triggers on ENTER_FRAME event
         * Redraws node graphics if _invalidDisplay == true
         **/
        protected function drawNode(event:Event = null):void {
            if ( this.parent != null 
                 && this._invalidDisplay) {
                     
                // are we in the middle of a suspendRedraw operation?
                if (this.svgRoot.viewer && this.svgRoot.viewer.isSuspended) {
                    return;
                }
                
                this._invalidDisplay = false;
                if (this._xml != null) {
                    drawSprite.graphics.clear();

                    if (!this._parsedChildren) {
                        this.parseChildren();
                        this._parsedChildren = true;
                    }

                    // sets x, y, rotate, and opacity
                    this.setAttributes();

                    if (this.getStyleOrAttr('visibility') == 'hidden') {
                        // SVG spec says visibility='hidden' should fully draw
                        // the shape with full stroke widths, etc., 
                        // just make it invisible. It also states that
                        // all children should be invisible _unless_ they
                        // explicitly have a visibility set to 'visible'.
                        this.setVisibility('hidden');
                    } else {
                        this.setVisibility('visible');
                    }
                    
                    if (this.getStyleOrAttr('display') == 'none') {
                        this.visible = false;
                    }
                    else {
                        this.visible = true;
                        // <svg> nodes get an implicit mask of their height and width
                        if (this is SVGSVGNode) {
                            this.applyDefaultMask();
                        }

                        this.generateGraphicsCommands();
                        this.transformNode();
                        this.draw();

                        this.applyClipPathMask();
                        this.applyViewBox();
                        this.setupFilters();
                    }
                }
                
                this.removeEventListener(Event.ENTER_FRAME, drawNode);

                if (this.xml.@id)  {
                    this.svgRoot.invalidateReferers(this.xml.@id);
                }

                if (getPatternAncestor() != null) {
                    this.svgRoot.invalidateReferers(getPatternAncestor().id);
                }
            }
            
            if (!this._initialRenderDone && this.parent) {
                this.attachEventListeners();
                this._initialRenderDone = true;
                this.svgRoot.renderFinished();
            }
        }

        protected function setAttributes():void {
            this.loadAttribute('x');
            this.loadAttribute('y');
            this.loadAttribute('rotate','rotation');
            this.loadAttribute('opacity', 'alpha', true);
            if (this.getStyleOrAttr('pointer-events') == 'none') {
                this.mouseEnabled = false;
                this.mouseChildren = false;
            }
            else {
                this.mouseEnabled = true;
                this.mouseChildren = true;
            }
        }

        /**
         * Load an XML attribute into the current node
         * 
         * @param name Name of the XML attribute to load
         * @param field Name of the node field to set. If null, the name attribute will be used as the field attribute.
         * @param applyStyle Boolean Optional parameter that controls whether we
         * will look in this node's style value if the given name is not in
         * the node's attribute list. Defaults to false.
         **/
        protected function loadAttribute(name:String, field:String = null,
                                         applyStyle:Boolean = false):void {
            if (field == null) {
                field = name;
            }
            var tmp:String = this.getStyleOrAttr(name);
            if (tmp != null) {
                switch (name) {
                    case 'x':
                        drawSprite[field] = SVGColors.cleanNumber2(tmp, this.getWidth());
                        break;
                    case 'y':
                        drawSprite[field] = SVGColors.cleanNumber2(tmp, this.getHeight());
                        break;
                    case 'rotate':
                        drawSprite[field] = SVGColors.cleanNumber(tmp);
                        break;
                    case 'opacity':
                        drawSprite[field] = SVGColors.cleanNumber(tmp);
                        break;
                }
            }
        } 

        /** Sets this node and all its children to the given visibility value.
            If a child has an explicit visibility setting then that is retained
            independent of what we set here.
            
            @param visible - If 'visible', sets this node to be visible. 
            The value 'hidden' will hide it.
            @param recursive - Internal variable. Should not set. */
        protected function setVisibility(visible:String, 
                                         recursive:Boolean = false):void {
            // FIXME: Turn this into an iterative rather than a recursive
            // method
            //this.dbg('setVisibility, this='+this.xml.localName()+', visible='+visible+', recursive='+recursive);
            // ignore if we have our own visibility value and we are a recursive
            // call
            if (this.getStyleOrAttr('visibility') == null 
                || recursive == false) {
                if (visible == 'visible') {
                    drawSprite.alpha = SVGColors.cleanNumber(this.getStyleOrAttr('opacity'));
                } else {
                    drawSprite.alpha = 0;
                }
            }
            
            // set on all our children
            var child:DisplayObject;
            for (var i:uint = 0; i < viewBoxSprite.numChildren; i++) {
                child = viewBoxSprite.getChildAt(i);
                if (child is SVGNode) {
                    SVGNode(child).setVisibility(visible, true);
                }
            }
        }

        // <svg> and <image> nodes get an implicit mask of their height and width
        public function applyDefaultMask():void {
            if (   (this.getAttribute('width') != null)
                && (this.getAttribute('height') != null) ) {
                if (transformSprite.mask == null) {
                    var myMask:Shape = new Shape();
                    transformSprite.parent.addChild(myMask);
                    transformSprite.mask = myMask;
                }
                if (transformSprite.mask is Shape) {
                    Shape(transformSprite.mask).graphics.clear();
                    Shape(transformSprite.mask).graphics.beginFill(0x000000);
                    Shape(transformSprite.mask).graphics.drawRect(drawSprite.x, drawSprite.y, this.getWidth(), this.getHeight());
                    Shape(transformSprite.mask).graphics.endFill();
                }
            }
        }

        /** 
         * Called to generate AS3 graphics commands from the SVG instructions
         **/
        protected function generateGraphicsCommands():void {
            this._graphicsCommands = new  Array();    
        }

        /**
         * Perform transformations defined by the transform attribute 
         **/
        public function transformNode():void {
            transformSprite.transform.matrix = new Matrix();
            this.loadAttribute('x');    
            this.loadAttribute('y');

            // XXX hack because tspan x,y apparently replaces
            // the parent text x,y instead of offsetting the
            // parent like every other node. the 'correct'
            // calculation is commented out because it does
            // not work currently
            if (this is SVGTspanNode) {
                this.x = 0;
                this.y = 0;
                //this.x = this.x - this.parent.x;
                //this.y = this.y - this.parent.y;
            }
            
            this.loadAttribute('rotate', 'rotation');

            // Apply transform attribute 
            var trans:String = this.getAttribute('transform');
            if (trans) {
                transformSprite.transform.matrix = this.parseTransform(trans,
                                                            transformSprite.transform.matrix.clone());
            }
            
            var animMatrix:Matrix = this.getAllAnimsTransform();
            if (animMatrix != null) {
                var newMatrix:Matrix = transformSprite.transform.matrix.clone();
                newMatrix.concat(animMatrix);
                transformSprite.transform.matrix = newMatrix;
            }
        }

        public function parseTransform(trans:String, baseMatrix:Matrix = null):Matrix {
            if (!baseMatrix) {
                baseMatrix = new Matrix();
            }
            
            if (trans != null) {
                var transArray:Array = trans.match(/\S+\(.*?\)/sg);
                transArray.reverse();
                for each(var tran:String in transArray) {
                    var tranArray:Array = tran.split('(',2);
                    if (tranArray.length == 2)
                    {
                        var command:String = String(tranArray[0]);
                        var args:String = String(tranArray[1]);
                        args = args.replace(')','');
                        args = args.replace(/\s+/sg,","); //Replace spaces with a comma
                        args = args.replace(/,{2,}/sg,","); // Remove any extra commas
                        args = args.replace(/^,/, ''); //Remove leading comma
                        args = args.replace(/,$/, ''); //Remove trailing comma
                        var argsArray:Array = args.split(',');

                        var nodeMatrix:Matrix = new Matrix();
                        switch (command) {
                            case "matrix":
                                if (argsArray.length == 6) {
                                    nodeMatrix.a = argsArray[0];
                                    nodeMatrix.b = argsArray[1];
                                    nodeMatrix.c = argsArray[2];
                                    nodeMatrix.d = argsArray[3];
                                    nodeMatrix.tx = argsArray[4];
                                    nodeMatrix.ty = argsArray[5];
                                }
                                break;

                            case "translate":
                                if (argsArray.length == 1) {
                                    nodeMatrix.tx = argsArray[0]; 
                                }
                                else if (argsArray.length == 2) {
                                    nodeMatrix.tx = argsArray[0]; 
                                    nodeMatrix.ty = argsArray[1]; 
                                }
                                break;

                            case "scale":
                                if (argsArray.length == 1) {
                                    nodeMatrix.a = argsArray[0];
                                    nodeMatrix.d = argsArray[0];
                                }
                                else if (argsArray.length == 2) {
                                    nodeMatrix.a = argsArray[0];
                                    nodeMatrix.d = argsArray[1];
                                }
                                break;
                                
                            case "skewX":
                                nodeMatrix.c = Math.tan(argsArray[0] * Math.PI / 180.0);
                                break;
                                
                            case "skewY":
                                nodeMatrix.b = Math.tan(argsArray[0] * Math.PI / 180.0);
                                break;
                                
                            case "rotate":
                                if (argsArray.length == 3) {
                                    nodeMatrix.translate(-argsArray[1], -argsArray[2]);
                                    nodeMatrix.rotate(Number(argsArray[0])* Math.PI / 180.0);
                                    nodeMatrix.translate(argsArray[1], argsArray[2]); 
                                }
                                else {
                                    nodeMatrix.rotate(Number(argsArray[0])* Math.PI / 180.0);
                                }
                                break;
                                
                            default:
                                //this.dbg('Unknown Transformation: ' + command);
                        }
                        baseMatrix.concat(nodeMatrix);
                    }
                }
            }
            
            return baseMatrix;
        }

        protected function draw():void {
            var firstX:Number = 0;
            var firstY:Number = 0;

            for each (var command:Array in this._graphicsCommands) {
                switch(command[0]) {
                    case "SF":
                        this.nodeBeginFill();
                        break;
                    case "EF":
                        drawSprite.graphics.lineStyle(0, 0, 0);
                        this.nodeEndFill();
                        break;
                    case "M":
                        drawSprite.graphics.lineStyle(0, 0, 0);
                        drawSprite.graphics.moveTo(command[1], command[2]);
                        firstX = command[1];
                        firstY = command[2];
                        this.nodeBeginStroke();
                        break;
                    case "L":
                        drawSprite.graphics.lineTo(command[1], command[2]);
                        break;
                    case "C":
                        drawSprite.graphics.curveTo(command[1], command[2],command[3], command[4]);
                        break;
                    case "Z":
                        drawSprite.graphics.lineTo(firstX, firstY);
                        break;
                    case "LINE":
                        this.nodeBeginFill();
                        drawSprite.graphics.moveTo(command[1], command[2]);
                        drawSprite.graphics.lineTo(command[3], command[4]);
                        this.nodeEndFill();                
                        break;
                    case "RECT":
                        this.nodeBeginFill();
                        if (command.length == 5) {
                            drawSprite.graphics.drawRect(command[1], command[2],command[3], command[4]);
                        }
                        else {
                            drawSprite.graphics.drawRoundRect(command[1], command[2],command[3], command[4], command[5], command[6]);
                        }
                        this.nodeEndFill();                
                        break;        
                    case "CIRCLE":
                        this.nodeBeginFill();
                        drawSprite.graphics.drawCircle(command[1], command[2], command[3]);
                        this.nodeEndFill();
                        break;
                    case "ELLIPSE":
                        this.nodeBeginFill();                        
                        drawSprite.graphics.drawEllipse(command[1], command[2],command[3], command[4]);
                        this.nodeEndFill();
                        break;
                }
            }
        }

        /** 
         * Called at the start of drawing an SVG element.
         * Sets fill and stroke styles
         **/
        protected function nodeBeginFill():void {
            //Fill
            var color_and_alpha:Array = [0, 0];
            var color_core:Number = 0;
            var color_alpha:Number = 0;
            var fill_alpha:Number = 0;

            var fill:String = this.getStyleOrAttr('fill');
            if ( (fill != 'none') && (fill != null) && (this.getStyleOrAttr('visibility') != 'hidden') ) {
                var matches:Array = fill.match(/url\(#([^\)]+)\)/si);
                if (matches != null && matches.length > 0) {
                    var fillName:String = matches[1];
                    this.svgRoot.addReference(this, fillName);
                    var fillNode:SVGNode = this.svgRoot.getNode(fillName);
                    if (!fillNode) {
                         // this happens normally
                         //this.dbg("Gradient " + fillName + " not (yet?) available for " + this.xml.@id);
                    }
                    if (fillNode is SVGGradient) {
                        SVGGradient(fillNode).beginGradientFill(this);
                    }
                    else if (fillNode is SVGPatternNode) {
                        SVGPatternNode(fillNode).beginPatternFill(this);
                    }
                }
                else {
                    if (fill == 'currentColor') {
                        fill = this.getStyleOrAttr('color');
                    }
                    color_and_alpha = SVGColors.getColorAndAlpha(fill);
                    color_core = color_and_alpha[0];
                    color_alpha = color_and_alpha[1];
                    fill_alpha = SVGColors.cleanNumber( this.getStyleOrAttr('fill-opacity') ) * color_alpha;
                    drawSprite.graphics.beginFill(color_core, fill_alpha);
                }
            }
            nodeBeginStroke();
        }

        protected function nodeBeginStroke():void {
            //Stroke
            var line_color:Number;
            var line_alpha:Number;
            var line_width:Number;

            var stroke:String = this.getStyleOrAttr('stroke');
            if ( (stroke == 'none') || (stroke == '') || (this.getStyleOrAttr('visibility') == 'hidden') ) {
                line_alpha = 0;
                line_color = 0;
                line_width = 0;
            }
            else {
                if (stroke == 'currentColor') {
                    stroke = this.getStyleOrAttr('color');
                }
                line_color = SVGColors.cleanNumber(SVGColors.getColor(stroke));
                line_alpha = SVGColors.cleanNumber(this.getStyleOrAttr('stroke-opacity'));
                line_width = SVGColors.cleanNumber(this.getStyleOrAttr('stroke-width'));
            }

            var capsStyle:String = this.getStyleOrAttr('stroke-linecap');
            if (capsStyle == 'round'){
                capsStyle = CapsStyle.ROUND;
            }
            else if (capsStyle == 'square'){
                capsStyle = CapsStyle.SQUARE;
            }
            else {
                capsStyle = CapsStyle.NONE;
            }
            
            var jointStyle:String = this.getStyleOrAttr('stroke-linejoin');
            if (jointStyle == 'round'){
                jointStyle = JointStyle.ROUND;
            }
            else if (jointStyle == 'bevel'){
                jointStyle = JointStyle.BEVEL;
            }
            else {
                jointStyle = JointStyle.MITER;
            }
            
            var miterLimit:String = this.getStyleOrAttr('stroke-miterlimit');
            if (miterLimit == null) {
                miterLimit = '4';
            }
            
            drawSprite.graphics.lineStyle(line_width, line_color, line_alpha, false, LineScaleMode.NORMAL,
                                          capsStyle, jointStyle, SVGColors.cleanNumber(miterLimit));

            if ( (stroke != 'none') && (stroke != '')  && (this.getStyleOrAttr('visibility') != 'hidden') ) {
                var strokeMatches:Array = stroke.match(/url\(#([^\)]+)\)/si);
                if (strokeMatches != null && strokeMatches.length > 0) {
                    var strokeName:String = strokeMatches[1];
                    this.svgRoot.addReference(this, strokeName);
                    var strokeNode:SVGNode = this.svgRoot.getNode(strokeName);
                    if (!strokeNode) {
                         // this happens normally
                         //this.dbg("stroke gradient " + strokeName + " not (yet?) available for " + this.xml.@id);
                    }
                    if (strokeNode is SVGGradient) {
                         SVGGradient(strokeNode).lineGradientStyle(this, line_alpha);
                    }
                }
            }
        }
        
        /** 
         * Called at the end of drawing an SVG element
         **/
        protected function nodeEndFill():void {
            drawSprite.graphics.endFill();
        }

        /**
         * Check value of x against _minX and _maxX, 
         * Update values when appropriate
         **/
        protected function setXMinMax(value:Number):void {          
            if (_firstX) {
                _firstX = false;
                this.xMax = value;
                this.xMin = value;
                return;
            }
            
            if (value < this.xMin) {
                this.xMin = value;
            }
            if (value > this.xMax) {
                this.xMax = value;
            }
        }
        
        /**
         * Check value of y against _minY and _maxY, 
         * Update values when appropriate
         **/
        protected function setYMinMax(value:Number):void {
            if (_firstY) {
                _firstY = false;
                this.yMax = value;
                this.yMin = value;
                return;
            }
            
            if (value < this.yMin) {
                this.yMin = value;
            }
            if (value > this.yMax) {
                this.yMax = value;
            }
        }

        public function applyViewBox():void {
            // Apply viewbox transform
            var viewBox:String = this.getAttribute('viewBox');
            var preserveAspectRatio:String = this.getAttribute('preserveAspectRatio');

            if ( (viewBox != null) || (preserveAspectRatio != null) ) {
                var newMatrix:Matrix = new Matrix();

                if (preserveAspectRatio == null) {
                    preserveAspectRatio = 'xMidYMid meet';
                }

                /**
                 * Canvas, the viewport
                 **/
                var canvasWidth:Number = this.getWidth();
                var canvasHeight:Number = this.getHeight();

                /**
                 * Viewbox
                 **/
                var viewX:Number;
                var viewY:Number;
                var viewWidth:Number;
                var viewHeight:Number;
                if (viewBox != null) {
                    viewBox = viewBox.replace(/,/sg," "); //Replace commas with spaces
                    var points:Array = viewBox.split(/\s+/); //Split by white space 
                    viewX = SVGColors.cleanNumber(points[0]);
                    viewY = SVGColors.cleanNumber(points[1]);
                    viewWidth = SVGColors.cleanNumber(points[2]);
                    viewHeight = SVGColors.cleanNumber(points[3]);
                }
                else {
                    viewX = 0;
                    viewY = 0;
                    viewWidth = canvasWidth;
                    viewHeight = canvasHeight;
                }


                var oldAspectRes:Number = viewWidth / viewHeight;
                var newAspectRes:Number = canvasWidth /  canvasHeight;
                var cropWidth:Number;
                var cropHeight:Number;

                var alignMode:String = preserveAspectRatio.substr(0,8);
                var meetOrSlice:String = 'meet';
                if (preserveAspectRatio.indexOf('slice') != -1) {
                    meetOrSlice = 'slice';
                }

                /**
                 * Handle Scaling
                 **/
                if (alignMode == 'none') {
                    // stretch to fit viewport width and height

                    cropWidth = canvasWidth;
                    cropHeight = canvasHeight;
                }
                else {
                    if (meetOrSlice == 'meet') {
                        // shrink to fit inside viewport

                        if (newAspectRes > oldAspectRes) {
                            cropWidth = canvasHeight * oldAspectRes;
                            cropHeight = canvasHeight;
                        }
                        else {
                            cropWidth = canvasWidth;
                            cropHeight = canvasWidth / oldAspectRes;
                        }
    
                    }
                    else {
                        // meetOrSlice == 'slice'
                        // Expand to cover viewport.

                        if (newAspectRes > oldAspectRes) {
                            cropWidth = canvasWidth;
                            cropHeight = canvasWidth / oldAspectRes;
                        }
                        else {
                            cropWidth = canvasHeight * oldAspectRes;
                            cropHeight = canvasHeight;
                        }
    
                    }
                }
                var scaleX:Number = cropWidth / viewWidth;
                var scaleY:Number = cropHeight / viewHeight;
                newMatrix.translate(-viewX, -viewY);
                newMatrix.scale(scaleX, scaleY);

                /**
                 * Handle Alignment
                 **/
                var borderX:Number;
                var borderY:Number;
                var translateX:Number;
                var translateY:Number;
                if (alignMode != 'none') {
                    translateX=0;
                    translateY=0;
                    var xAlignMode:String = alignMode.substr(0,4);
                    switch (xAlignMode) {
                        case 'xMin':
                            break;
                        case 'xMax':
                            translateX = canvasWidth - cropWidth;
                            break;
                        case 'xMid':
                        default:
                            borderX = canvasWidth - cropWidth;
                            translateX = borderX / 2.0;
                            break;
                    }
                    var yAlignMode:String = alignMode.substr(4,4);
                    switch (yAlignMode) {
                        case 'YMin':
                            break;
                        case 'YMax':
                            translateY = canvasHeight - cropHeight;
                            break;
                        case 'YMid':
                        default:
                            borderY = canvasHeight - cropHeight;
                            translateY = borderY / 2.0;
                            break;
                    }
                    newMatrix.translate(translateX, translateY);
                }
                viewBoxSprite.transform.matrix = newMatrix;
            }
        }

        protected function applyClipPathMask():void {
            var attr:String;
            var match:Array;
            var node:SVGNode;
            var matrix:Matrix;

            attr = this.getStyleOrAttr('mask');
            if (!attr) {
                attr = this.getAttribute('clip-path');
            }

            if (attr) {
               match = attr.match(/url\(\s*#(.*?)\s*\)/si);
               if (match.length == 2) {
                   attr = match[1];
                   node = this.svgRoot.getNode(attr);
                   if (node) {
                       this.removeMask();

                       var newMask:SVGNode = node.clone();
                       newMask.isMask = true;

                       addSVGChild(transformSprite, newMask);
                       clipSprite.mask = newMask;

                       newMask.visible = true;
                       clipSprite.cacheAsBitmap = true;
                       newMask.cacheAsBitmap = true;
                   }
               }
            }
        }

        protected function removeMask():void {
            if (clipSprite.mask) {
                clipSprite.mask.parent.removeChild(clipSprite.mask);
                clipSprite.mask = null;
            }
        }

        /**
         * Add any assigned filters to node
         **/
        protected function setupFilters():void {
            var filterName:String = this.getStyleOrAttr('filter');
            if ( (filterName != null) && (filterName != '') && (filterName != 'none') ) {
                var matches:Array = filterName.match(/url\(#([^\)]+)\)/si);
                if (matches.length > 0) {
                    filterName = matches[1];
                    var filterNode:SVGNode = this.svgRoot.getNode(filterName);
                    if (filterNode) {
                        drawSprite.filters = SVGFilterNode(filterNode).getFilters(this);
                    }
                    else {
                        //this.dbg("filter " + filterName + " not (yet?) available for " + this.xml.@id);
                        // xxx add reference
                    }
                }
            }
        }

        protected function attachEventListeners():void {
            var action:String;

            action = this.getAttribute('onclick', null, false);
            if (action) {
                this.svgRoot.addActionListener(MouseEvent.CLICK, drawSprite);
            }

            action = this.getAttribute('onmousedown', null, false);
            if (action) {
                this.svgRoot.addActionListener(MouseEvent.MOUSE_DOWN, drawSprite);
            }

            action = this.getAttribute('onmouseup', null, false);
            if (action) {
                this.svgRoot.addActionListener(MouseEvent.MOUSE_UP, drawSprite);
            }

            action = this.getAttribute('onmousemove', null, false);
            if (action) {
                this.svgRoot.addActionListener(MouseEvent.MOUSE_MOVE, drawSprite);
            }

            action = this.getAttribute('onmouseover', null, false);
            if (action) {
                this.svgRoot.addActionListener(MouseEvent.MOUSE_OVER, drawSprite);
            }

            action = this.getAttribute('onmouseout', null, false);
            if (action) {
                this.svgRoot.addActionListener(MouseEvent.MOUSE_OUT, drawSprite);
            }
        }
                

        /*
         * Node registration triggered by stage add / remove
         */

        protected function onAddedToStage(event:Event):void {
            this.registerSelf();
            if (this.original) {
                this.original.registerClone(this);
            }
        }

        protected function onRemovedFromStage(event:Event):void {
            this.unregisterSelf();
            if (this.original) {
                this.original.unregisterClone(this);
            }
        }

        protected function registerSelf():void {
            if (this._isClone || (getMaskAncestor() != null)) {
                return;
            }
            
            this.svgRoot.registerGUID(this);
            
            var id:String = this.getAttribute('id');

            if (id == _id) {
                return;
            }

            if (_id) {
                this.svgRoot.unregisterNode(this);
            }

            if (id && id != "") {
                _id = id;
                this.svgRoot.registerNode(this);
            }
        }

        protected function unregisterSelf():void {
            this.svgRoot.unregisterGUID(this);
            
            if (this._id) {
                this.svgRoot.unregisterNode(this);
                _id = null;
            }
        }

        /*
         * Attribute Handling
         */

        /** 
         * Gets an XML attribute from this node
         *
         * @param name XML attribute to retrieve from SVG XML.
         * @param defaultValue Default value to return if this attribute is
         * not defined. Defaults to null.
         * @param inherit Whether to look up the inheritance chain if this
         * property is inherited. Defaults to true.
         * @param applyAnimations Boolean, optional, defaults to true. Controls
         * whether we apply any SMIL animations that might be in flight to the
         * attribute. If false, then we return the base actual set value on
         * this node without reference to any animation changes.
         * @param applyStyle Boolean, optional, defaults to false. Controls whether
         * we get and set values from this node's style values as well as its
         * attribute values. If false, then we don't check or set a given
         * attribute name against the style value.
         * 
         * @return Returns the XML attribute value, or the defaultValue.
         **/
        public function getAttribute(name:String, 
                                     defaultValue:* = null,
                                     inherit:Boolean = true,
                                     applyAnimations:Boolean = true,
                                     applyStyle:Boolean = false):* {
            var value:String = this._getAttribute(name, defaultValue,
                                                  inherit, applyAnimations,
                                                  applyStyle);
            
            if (value !== null && value != 'inherit') {
                return value;
            }
            
            if (value == "inherit") {
                value = null;
            }
            
            if (ATTRIBUTES_NOT_INHERITED.indexOf(name) != -1) {            
                if (defaultValue == null) {
                    if (name == 'opacity') {
                        return '1';
                    }
                    // default fall through
                }
                return defaultValue;        
            }
            
            if (inherit && (this.getSVGParent() != null)) {
                return SVGNode(this.getSVGParent()).getAttribute(name, defaultValue, true, 
                                                                 applyAnimations, applyStyle);
            }
            
            return defaultValue;       
        }
        
        /**
         *
         * This method retrieves the attribute from the current node only and is
         * used as a helper for getAttribute, which has css parent inheritance logic.
         *
         **/
        protected function _getAttribute(name:String, defaultValue:* = null,
                                         inherit:Boolean = true,
                                         applyAnimations:Boolean = true,
                                         applyStyle:Boolean = false):* {
            var value:String;
            
            // If we are rendering a mask, then use a simple black fill.
            if (this.getMaskAncestor() != null) {
                if (  (name == 'opacity')
                    || (name == 'fill-opacity')
                    || (name == 'stroke-width')
                    || (name == 'stroke-opacity') ) {
                    return '1';
                }

                if (name == 'fill') {
                    return 'black';
                }

                if (name == 'stroke') {
                    return 'none';
                }

                if (name == 'filter') {
                    return 'none';
                }
            }

            if (applyAnimations) {
                value = getAnimAttribute(name, defaultValue, inherit,
                                         applyStyle);
                if (value !== null) {
                    return value;
                }
            }
           
            if (name == "href") {
                //this._xml@href handled normally
                value = this._xml.@xlink::href;                             
                if (value !== null && (value != "")) {
                    return value;
                }
            }

            if (name == "base") {
                value = this._xml.@aaa::base;                             
                if (value !== null && (value != "")) {
                    return value;
                }
            }
            
            if (applyStyle && _styles.hasOwnProperty(name)) {
                return (_styles[name]);
            }
           
            var xmlList:XMLList = this._xml.attribute(name);
            
            if (xmlList.length() > 0) {
                return xmlList[0].toString();
            }
 
            return null;
        }
        
        public function getStyleOrAttr(name:String, defaultValue:* = null,
                                       inherit:Boolean = true,
                                       applyAnimations:Boolean = true):* {
            return getAttribute(name, defaultValue, inherit, applyAnimations, true);
        }
        
        // process all animations
        public function getAnimAttribute(name:String, defaultValue:* = null,
                                         inherit:Boolean = true,
                                         useStyle:Boolean = false):String {
            var animation:SVGAnimateNode;

            // transform is handled by getAllAnimTransforms
            if (name == "transform")
                return null;
 
            var foundAnimation:Boolean = false;
            for each(animation in animations) {
                if (animation.getAttributeName() == name) {
                    foundAnimation = true;
                }
            }
            if (!foundAnimation)
                return null;
 
            var isAdditive:Boolean = true;

            // Start with base value
            var baseVal:String = getAttribute(name, defaultValue, inherit, false,
                                              useStyle);

            var animVal:Number;
            if (baseVal) {
                animVal = SVGUnits.cleanNumber(baseVal);
            }
            else {
                animVal= 0;
            }
             
            // Handle discrete string values
            var discreteStringVal:String;
            // XXX This should sort by priority (activation order) 
            // Add or replace with animations
            for each(animation in animations) {
                if (   animation.getAttributeName() == name
                    && animation.isEffective() ) {
                    if (animation.isAdditive()) {
                        animVal = animVal + SVGUnits.cleanNumber(animation.getAnimValue());
                    }
                    else {
                        animVal = SVGUnits.cleanNumber(animation.getAnimValue());
                        discreteStringVal = animation.getAnimValue();
                    }
                }
            }
            return String(animVal);
        }

        // process all transform animations
        // xxx not fully implemented
        public function getAllAnimsTransform():Matrix {
            var rotateTransform:Matrix = new Matrix();
            var scaleTransform:Matrix = new Matrix();
            var skewXTransform:Matrix = new Matrix();
            var skewYTransform:Matrix = new Matrix();
            var translateTransform:Matrix = new Matrix();

            // XXX This should sort by priority (activation order) 
            for each(var animation:SVGAnimateNode in animations) {
                if (animation is SVGAnimateTransformNode
                    && animation.isEffective()) {

                    if (animation.isAdditive()) {
                        switch (SVGAnimateTransformNode(animation).getTransformType() ) {
                            case "rotate":
                                rotateTransform.concat(SVGAnimateTransformNode(animation).getAnimTransform());
                                break;
                            case "scale":
                                scaleTransform.concat(SVGAnimateTransformNode(animation).getAnimTransform());
                                break;
                            case "skewX":
                                skewXTransform.concat(SVGAnimateTransformNode(animation).getAnimTransform());
                                break;
                            case "skewY":
                                skewYTransform.concat(SVGAnimateTransformNode(animation).getAnimTransform());
                                break;
                            case "translate":
                                translateTransform.concat(SVGAnimateTransformNode(animation).getAnimTransform());
                                break;
                        }
                    }
                    else {
                        rotateTransform = new Matrix();
                        scaleTransform = new Matrix();
                        skewXTransform = new Matrix();
                        skewYTransform = new Matrix();
                        translateTransform = new Matrix();
                        switch (SVGAnimateTransformNode(animation).getTransformType() ) {
                            case "rotate":
                                rotateTransform = SVGAnimateTransformNode(animation).getAnimTransform();
                                break;
                            case "scale":
                                scaleTransform = SVGAnimateTransformNode(animation).getAnimTransform();
                                break;
                            case "skewX":
                                skewXTransform = SVGAnimateTransformNode(animation).getAnimTransform();
                                break;
                            case "skewY":
                                skewYTransform = SVGAnimateTransformNode(animation).getAnimTransform();
                                break;
                            case "translate":
                                translateTransform = SVGAnimateTransformNode(animation).getAnimTransform();
                                break;
                        }
                    }
                }
            }
            var animTransform:Matrix= new Matrix();
            animTransform.concat(rotateTransform);
            animTransform.concat(scaleTransform);
            animTransform.concat(skewXTransform);
            animTransform.concat(skewYTransform);
            animTransform.concat(translateTransform);
            return animTransform;
        }

        public function setAttribute(name:String, value:String):void {
            if (name == "style") {
                this._xml.@style = value;
                this.parseStyle();
            }
            else {
                this._xml.@[name] = value;
            }
            
            switch (name) {
                case 'onclick':
                case 'onmousedown':
                case 'onmousemove':
                case 'onmouseout':
                case 'onmouseover':
                case 'onmouseup':
                case 'onmousedown':
                    this.attachEventListeners();
                    break;

                case 'transform':
                case 'viewBox':
                case 'x':
                case 'y':
                case 'rotation':
                    this.transformNode();
                    this.applyViewBox();
                    break;

                default:
                    this.invalidateDisplay();
                    if (name == 'style' &&
                            ( value.indexOf('visibility') != -1
                            || value.indexOf('display') != -1 )) {
                        this.invalidateChildren();
                    }
                    break;
            }
            this.updateClones();
            if (getPatternAncestor() != null) {
                this.svgRoot.invalidateReferers(getPatternAncestor().id);
            }
        }
        
        /** Sets a style attribute in the style="" string. Note that this
         *  leaves XML attributes alone. For examle, if you set 
         *  the fill style to 'red', the XML fill attribute will remain with
         *  its old value. 
         **/
        public function setStyle(name:String, value:String):void {
            //this.dbg('setStyle, name='+name+', value='+value);
            this._styles[name] = value;
            this.updateStyle();
            this.parseStyle();
            
            this.updateClones();

            this.invalidateDisplay();
            if (   (name == 'display' || name == 'visibility')
                || (name == 'style' &&
                        (   (value.indexOf('visibility') != -1 )
                         || (value.indexOf('display') != -1 ) ) ) ) {
                this.invalidateChildren();
            }
        }
        
        /** Gets a style attribute from the style="" string. Note that this
         *  leaves XML attributes alone. For examle, if you set 
         *  the fill style to 'red', the XML fill attribute will remain with
         *  its old value. Note that style values do not reflect changes
         *  that might apply due to SMIL animations; use getAttribute to
         *  an attribute that might have come into existence as part of a 
         *  SMIL animation.
         *
         *  @param name The style name, such as fill or stroke-width. Dashed
         *  style names will automatically be converted into camel case.
         *  @param defaultValue The default value to return if none is present.
         *  Defaults to null.
         *  @param inherit Whether to look up the inheritance chain if this
         *  property is inherited. Defaults to true.
         *
         *  @return The style value, or null if it is not present.
         **/
        public function getStyle(name:String, defaultValue:* = null, 
                                 inherit:Boolean = true):* {
            var value:String = this._getStyle(name);
            if (value !== null) {
                return value;
            }
                     
            if (_styles.hasOwnProperty(name)) {
                value = _styles[name];
            }
            
            if (value == "inherit") {
                value = null;
            }
            
            if (value !== null) {
                return value;
            }
            
            if (inherit && this.getSVGParent()) {
                return this.getSVGParent().getStyle(name, defaultValue, inherit);
            }
            
            return defaultValue;
        }
        
        /** This method retrieves the style from the current node only and is
         *  used as a helper for getStyle. 
         **/
        protected function _getStyle(name:String):String {
            var value:String;
            
            // If we are rendering a mask, then use a simple black fill.
            if (this.getMaskAncestor() != null) {
                if ((name == 'opacity')
                    || (name == 'fill-opacity')
                    || (name == 'stroke-width')
                    || (name == 'stroke-opacity') ) {
                    return '1';
                }

                if (name == 'fill') {
                    return 'black';
                }

                if (name == 'stroke') {
                    return 'none';
                }

                if (name == 'filter') {
                    return null;
                }
            }
            
            if (this.original && (this.getSVGParent() is SVGUseNode)) {
                //Node is the top level of a clone
                //Check for an override value from the parent
                value = SVGNode(this.getSVGParent()).getStyle(name, null, false);
                if (value !== null) {
                    return value;
                }
            }

            if (_styles.hasOwnProperty(name)) {
                return (_styles[name]);
            }
 
            return null;
        }

        private function parseStyle():void {
            //Get styling from XML attribute 'style'
            _styles = new Object();
            
            var xmlList:XMLList = this._xml.attribute('style');
            if (xmlList.length() > 0) {
                var styleString:String = xmlList[0].toString();
                
                // only one style value given, with no trailing semicolon?
                if (this._xml.@style.length()  && styleString.indexOf(';') == -1) {
                    // update our internal string to be correct moving forward
                    this._xml.@style = styleString + ';';
                    styleString += ';';
                }
                
                var styles:Array = styleString.split(';');
                for each(var style:String in styles) {
                    var styleSet:Array = style.split(':');
                    if (styleSet.length == 2) {
                        var attrName:String = SVGColors.trim(styleSet[0]);
                        var attrValue:String = SVGColors.trim(styleSet[1]);                        
                        this._styles[attrName] = attrValue;
                    }
                }
            }
        }
 
       /**
         * Update style attribute from _styles
         * <node style="...StyleString...">
         * 
         **/ 
        private function updateStyle():void {
            var newStyleString:String = '';
            
            for (var key:String in this._styles) {
                newStyleString += key + ':' + this._styles[key] + ';';
            }
            
            this._xml.@style = newStyleString;
        }
        
        /**
         * Returns true if this node can have text children. Subclasses
         * should override this if they want to have text node children.
         */
        public function hasText():Boolean {
            return false;
        }
        
        /**
         * Returns any text content this node might have as a child.
         */
        public function getText():String {
            return this._xml.text().toString();
        }
        
        /**
         * Sets any text content this node might have as a child.
         */
        public function setText(newValue:String):void {
            // subclasses should implement this if they want to have text
            throw new Error("Unimplemented");
        }
        
        public function onRegisterFont(fontFamily:String):void {
        }

        /**
         * Force a redraw of a node
         **/
        public function invalidateDisplay():void {
            if (this._invalidDisplay == false) {
                this._invalidDisplay = true;
                this.addEventListener(Event.ENTER_FRAME, drawNode);
            }            
        }

        public function invalidateChildren():void {
            var child:DisplayObject;
            for (var i:uint = 0; i < viewBoxSprite.numChildren; i++) {
                child = viewBoxSprite.getChildAt(i);
                if (child is SVGNode) {
                    SVGNode(child).invalidateDisplay();
                    SVGNode(child).invalidateChildren();
                }
            }
        }
 
        /*
         * Clone Handlers
         */

        public function clone():SVGNode {
            var nodeClass:Class = getDefinitionByName(getQualifiedClassName(this)) as Class;
            var newXML:XML = this._xml.copy();

            var node:SVGNode = new nodeClass(this.svgRoot, newXML, this) as SVGNode;

            return node;
        }

        public function registerClone(clone:SVGNode):void {
            if (this._clones.indexOf(clone) == -1) {
               this._clones.push(clone);
            }
        }

        public function unregisterClone(clone:SVGNode):void {
            var index:int = this._clones.indexOf(clone);
            if (index > -1) {
                this._clones = this._clones.splice(index, 1);
            }
        }

        protected function updateClones():void {
            for (var i:uint = 0; i < this._clones.length; i++) {
               SVGNode(this._clones[i]).xml = this._xml.copy();
            }
        }

        public function get isClone():Boolean {
            return this._isClone;
        }
        
        /*
         * Animations
         */

        public function addAnimation(animation:SVGAnimateNode):void {
            if (animations.indexOf(animation) == -1) {
                animations.push(animation);
            }
        }

        public function removeAnimation(animation:SVGAnimateNode):void {
            if (animations.indexOf(animation) != -1) {
                animations.splice(animations.indexOf(animation), 1);
            }
        }

        /*
         * Misc Functions
         */

        /**
         * Remove all child nodes
         **/        
        protected function clearSVGChildren():void {
            while(viewBoxSprite.numChildren) {
                viewBoxSprite.removeChildAt(0);
            }
        }

        public function getWidth():Number {
            var parentWidth:Number=0;
            if (this.parent is SVGViewer) {
                parentWidth = SVGViewer(this.parent).getWidth();
            }
            if (this.getSVGParent() != null) {
                parentWidth = SVGNode(this.getSVGParent()).getWidth();
            }
            if (this.getAttribute('width') != null) {
                return SVGColors.cleanNumber2(this.getAttribute('width'), parentWidth);
            }

            // defaults to 100%
            return parentWidth;
        }

        public function getHeight():Number {
            var parentHeight:Number=0;
            if (this.parent is SVGViewer) {
                parentHeight=SVGViewer(this.parent).getHeight();
            }
            if (this.getSVGParent() is SVGNode) {
                parentHeight=SVGNode(this.getSVGParent()).getHeight();
            }
            if (this.getAttribute('height') != null) {
                return SVGColors.cleanNumber2(this.getAttribute('height'), parentHeight);
            }

            // defaults to 100%
            return parentHeight;
        }
        
        /** Appends an SVGNode both to our display list as well as to our
          * XML.
          **/
        public function appendSVGChild(child:SVGNode):SVGNode {
            this._xml.appendChild(child._xml);
            this.addSVGChildAt(child, viewBoxSprite.numChildren);
            this.invalidateDisplay();

            return child;
        }
        
        public function removeSVGChild(node:SVGNode):SVGNode {
            var child:DisplayObject;
            var i:uint;
            for (i = 0; i < viewBoxSprite.numChildren; i++) {
                child = viewBoxSprite.getChildAt(i);
                if (child == node) {
                    viewBoxSprite.removeChild(child);
                }
            }
            
            // unregister the element
            this.svgRoot.unregisterNode(node);
            
            // if we are dealing with a fake text node, change our
            // text node contents
            if (node is SVGDOMTextNode && this.hasText()) {
                this.setText(null);
            }
            
            // remove from our XML children
            for (i = 0; i < this._xml.children().length(); i++) {
                if (this._xml.children()[i].@__guid == node._xml.@__guid) {
                    delete this._xml.children()[i];
                    break;
                }
            }
            
            this.invalidateDisplay();
            
            return node;
        }
        
        /**
         * Adds newChild before refChild. Position is the position of refChild
         * to add newChild before.
         */
        public function insertSVGBefore(position:int, newChild:SVGNode, refChild:SVGNode):void {
            //this.dbg('insertSVGBefore, position='+position+', newChild='+newChild+', refChild='+refChild);
            // update our XML
            this._xml.insertChildBefore(refChild.xml, newChild.xml);
    
            // update our Flash display list
            viewBoxSprite.addChildAt(newChild, position);
            this.invalidateDisplay();
        }
        
        public function addSVGChildAt(child:SVGNode, index:int):SVGNode {
            // update XML
            if (child is SVGDOMTextNode) {
                if (this.hasText()) {
                    this.setText(child.xml.text());
                }
            } else {
                if (index == (this._xml.children().length() - 1)) {
                    this._xml.appendChild(child.xml);
                } else {
                    var insertBefore:XML = this._xml.children()[index];
                    this._xml.insertChildBefore(insertBefore, child.xml);
                }
            }

            // update our Flash display list
            viewBoxSprite.addChildAt(child, index);
            return child;
        }

        public function getMaskAncestor():SVGNode {
            var node:DisplayObject = this;
            if ( (node is SVGNode) && SVGNode(node).isMask)
                return SVGNode(node);
            while (node && !(node is SVGSVGNode)) {
                node=node.parent;
                if (node && (node is SVGNode) && SVGNode(node).isMask)
                    return SVGNode(node);
            }
            return null;
        }

        public function getPatternAncestor():SVGPatternNode {
            var node:DisplayObject = this;
            while (node && !(node is SVGSVGNode)) {
                node=node.parent;
                if (node is SVGPatternNode)
                    return SVGPatternNode(node);
            }
            return null;
        }
        
        public function getSVGParent():SVGNode {
            var node:DisplayObject = this;
            while (node) {
                node=node.parent;
                if (node is SVGNode) {
                    return SVGNode(node);
                }
            }
            return null;
        }
        
        public static function addSVGChild(parentSprite:Sprite, child:SVGNode):void {
            parentSprite.addChild(child);
            child.svgRoot.renderPending();
        }
        
        public static function targetToSVGNode(node:DisplayObject):SVGNode {
            if (node is SVGNode)
                return SVGNode(node);
            node=node.parent;
            while (node) {
                if (node is SVGNode)
                    return SVGNode(node);
                node=node.parent;
            }
            return null;
        }

        /**
         * Getters / Setters
        **/
        public function set xml(xml:XML):void {
            _xml = xml;

            this.clearSVGChildren();

            if (_xml) {
                this._parsedChildren = false;
                this.parseStyle();
                this.invalidateDisplay();
            }

            this.updateClones();
        }
        
        public function get xml():XML {
            return this._xml;
        }

        public function get id():String {
            var id:String = this._xml.@id;
            return id;
        }
        
        public function get guid():String {
            return this._xml.@__guid;
        }

        public function get invalidDisplay():Boolean {
            return this._invalidDisplay;
        }


        public function dbg(debugString:String):void {
            this.svgRoot.debug(debugString);
        }
        
        public function err(errorString:String):void {
            this.svgRoot.error(errorString);
        }
    }
}
