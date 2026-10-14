/* GPU map viewport. The 2D canvas above it is reserved for tools and proposals. */
class MapGpuViewport {
  constructor(canvas) {
    this.canvas = canvas;
    this.gl = canvas.getContext('webgl2', {alpha:false, antialias:false, preserveDrawingBuffer:false});
    if (!this.gl) throw new Error('WebGL2 is unavailable');
    const gl = this.gl;
    const vertex = `#version 300 es
      precision highp float;
      layout(location=0) in vec2 position;
      layout(location=1) in vec2 uv;
      layout(location=2) in vec4 color;
      uniform vec2 origin;
      uniform vec2 resolution;
      uniform float cell;
      out vec2 texcoord;
      out vec4 tint;
      void main() {
        vec2 pixel = origin + position * cell;
        gl_Position = vec4(pixel.x / resolution.x * 2.0 - 1.0,
                           1.0 - pixel.y / resolution.y * 2.0, 0.0, 1.0);
        texcoord = uv;
        tint = color;
      }`;
    const fragment = `#version 300 es
      precision mediump float;
      in vec2 texcoord;
      in vec4 tint;
      uniform sampler2D sheet;
      out vec4 pixel;
      void main() { pixel = texture(sheet, texcoord) * tint; }`;
    const shader = (type, source) => {
      const result = gl.createShader(type);
      gl.shaderSource(result, source); gl.compileShader(result);
      if (!gl.getShaderParameter(result,gl.COMPILE_STATUS)) throw Error(gl.getShaderInfoLog(result));
      return result;
    };
    const program = gl.createProgram();
    gl.attachShader(program,shader(gl.VERTEX_SHADER,vertex));
    gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fragment));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program,gl.LINK_STATUS)) throw Error(gl.getProgramInfoLog(program));
    this.program = program;
    this.origin = gl.getUniformLocation(program,'origin');
    this.resolution = gl.getUniformLocation(program,'resolution');
    this.cell = gl.getUniformLocation(program,'cell');
    const geometry = () => {
      const vao = gl.createVertexArray(), buffer = gl.createBuffer();
      gl.bindVertexArray(vao); gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
      gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0,2,gl.FLOAT,false,32,0);
      gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1,2,gl.FLOAT,false,32,8);
      gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2,4,gl.FLOAT,false,32,16);
      return {vao,buffer};
    };
    const base=geometry(), draft=geometry();
    this.vao=base.vao; this.buffer=base.buffer;
    this.draftVao=draft.vao; this.draftBuffer=draft.buffer;
    const white = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D,white);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,1,1,0,gl.RGBA,gl.UNSIGNED_BYTE,
      new Uint8Array([255,255,255,255]));
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);
    this.white = white;
    this.textures = new WeakMap();
    this.vertices = new Float32Array(); this.batches = [];
    this.draftVertices = new Float32Array(); this.draftBatches = [];
    canvas.addEventListener('webglcontextlost',(event) => event.preventDefault());
  }

  textureFor(image) {
    let texture = this.textures.get(image);
    if (texture) return texture;
    const gl = this.gl;
    texture = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D,texture);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,false);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR_MIPMAP_LINEAR);
    gl.generateMipmap(gl.TEXTURE_2D);
    this.textures.set(image,texture);
    return texture;
  }

  sceneData(bounds, tiles, drawables, options) {
    const vertices = [], batches = [];
    let current = null;
    const quad = (texture,x,y,width,height,uv,color) => {
      if (!current || current.texture !== texture) {
        current = {texture, first:vertices.length/8, count:0}; batches.push(current);
      }
      const [u0,v0,u1,v1] = uv;
      const corners = [[x,y,u0,v0],[x+width,y,u1,v0],[x+width,y+height,u1,v1],
        [x,y,u0,v0],[x+width,y+height,u1,v1],[x,y+height,u0,v1]];
      for (const corner of corners) vertices.push(...corner,...color);
      current.count += 6;
    };
    const rgba = (css) => {
      if (css.startsWith('#')) return [1,3,5].map((offset) => parseInt(css.slice(offset,offset+2),16)/255).concat(1);
      const [,h,s,l,a] = css.match(/hsla\((\d+),(\d+)%,(\d+)%,([.\d]+)\)/) || [];
      if (!h) return [1,1,1,1];
      const hue=Number(h)/60, sat=Number(s)/100, light=Number(l)/100;
      const chroma=(1-Math.abs(2*light-1))*sat, second=chroma*(1-Math.abs(hue%2-1));
      const choices=[[chroma,second,0],[second,chroma,0],[0,chroma,second],
        [0,second,chroma],[second,0,chroma],[chroma,0,second]];
      return choices[Math.floor(hue)%6].map((v) => v+light-chroma/2).concat(Number(a));
    };
    for (const tile of tiles) {
      const x=tile.x-1, y=-tile.y;
      quad(this.white,x,y,1,1,[0,0,1,1],rgba(options.classify(tile.atoms)));
      if (options.areas) {
        const area=tile.atoms.find((atom) => atom.startsWith('/area/'));
        if (area) quad(this.white,x,y,1,1,[0,0,1,1],rgba(options.areaColor(area)));
      }
    }
    for (const {atom,sx,sy} of drawables) {
      if (!options.visible(atom)) continue;
      const sprite=options.imageFor(atom);
      if (!sprite.loaded) continue;
      const image=sprite.img, texture=this.textureFor(image);
      const crop=sprite.crop || [0,0,image.naturalWidth,image.naturalHeight];
      const appearance=options.appearance[atom] || {};
      const layer=options.atomLayer(atom);
      const brightness=['power','atmos','disposals'].includes(layer) ? 2.1 : 1;
      const alpha=layer==='power'||layer==='atmos'||layer==='disposals' ?
        Math.max(.85,(appearance.alpha ?? 255)/255) : (appearance.alpha ?? 255)/255;
      const x=bounds.x1-1+sx/32+(appearance.pixel_x || 0)/32;
      const y=-bounds.y2+sy/32-(appearance.pixel_y || 0)/32;
      quad(texture,x,y,crop[2]/32,crop[3]/32,
        [crop[0]/image.naturalWidth,crop[1]/image.naturalHeight,
          (crop[0]+crop[2])/image.naturalWidth,(crop[1]+crop[3])/image.naturalHeight],
        [brightness,brightness,brightness,alpha]);
    }
    return {vertices:new Float32Array(vertices),batches};
  }

  setScene(bounds, tiles, drawables, options) {
    const {vertices,batches}=this.sceneData(bounds,tiles,drawables,options);
    this.vertices=vertices; this.batches=batches;
    const gl=this.gl;
    gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER,vertices,gl.STATIC_DRAW);
  }

  setDraftScene(bounds, tiles, drawables, options) {
    const {vertices,batches}=this.sceneData(bounds,tiles,drawables,options);
    this.draftVertices=vertices; this.draftBatches=batches;
    const gl=this.gl;
    gl.bindBuffer(gl.ARRAY_BUFFER,this.draftBuffer);
    gl.bufferData(gl.ARRAY_BUFFER,vertices,gl.DYNAMIC_DRAW);
  }

  draw(camera,cell,width,height,ratio) {
    const gl=this.gl;
    const pixelWidth=Math.ceil(width*ratio),pixelHeight=Math.ceil(height*ratio);
    if (this.canvas.width!==pixelWidth || this.canvas.height!==pixelHeight) {
      this.canvas.width=pixelWidth; this.canvas.height=pixelHeight;
    }
    gl.viewport(0,0,pixelWidth,pixelHeight);
    gl.clearColor(.063,.098,.106,1); gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(this.program);
    gl.uniform2f(this.origin,width/2-(camera.x-.5)*cell,height/2+(camera.y-.5)*cell);
    gl.uniform2f(this.resolution,width,height); gl.uniform1f(this.cell,cell);
    gl.activeTexture(gl.TEXTURE0);
    gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);
    for (const [vao,batches] of [[this.vao,this.batches],[this.draftVao,this.draftBatches]]) {
      gl.bindVertexArray(vao);
      for (const batch of batches) {
        gl.bindTexture(gl.TEXTURE_2D,batch.texture);
        gl.drawArrays(gl.TRIANGLES,batch.first,batch.count);
      }
    }
  }
}
