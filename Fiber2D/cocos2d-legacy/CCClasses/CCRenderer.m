/*
 * Cocos2D-SpriteBuilder: http://cocos2d.spritebuilder.com
 *
 * Copyright (c) 2014 Cocos2D Authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "objc/message.h"

#import "ccUtils.h"

#import "CCRenderer_Private.h"
#import "CCTexture_Private.h"
#import "CCShader_private.h"
#import "Fiber2D-Swift.h"

#import "CCCache.h"

#import "CCMetalSupport_Private.h"

@interface NSValue()

// Defined in NSValue+CCRenderer.m.
-(size_t)CCRendererSizeOf;

@end


#pragma mark Graphics Debug Helpers:

#if DEBUG

void CCRENDERER_DEBUG_PUSH_GROUP_MARKER(NSString *label){
    [[CCMetalContext currentContext].currentRenderCommandEncoder pushDebugGroup:label];
}

void CCRENDERER_DEBUG_POP_GROUP_MARKER(void){
    [[CCMetalContext currentContext].currentRenderCommandEncoder popDebugGroup];
}

void CCRENDERER_DEBUG_INSERT_EVENT_MARKER(NSString *label){
    [[CCMetalContext currentContext].currentRenderCommandEncoder insertDebugSignpost:label];
}

void CCRENDERER_DEBUG_CHECK_ERRORS(void) {
}

#endif


#pragma mark Draw Command.


@implementation CCRenderCommandDraw

-(instancetype)initWithMode:(CCRenderCommandDrawMode)mode renderState:(CCRenderState *)renderState firstIndex:(NSUInteger)firstIndex vertexPage:(NSUInteger)vertexPage count:(size_t)count globalSortOrder:(NSInteger)globalSortOrder;
{
	if((self = [super init])){
		_mode = mode;
		_renderState = [renderState retain];
		_firstIndex = firstIndex;
		_vertexPage = vertexPage;
		_count = count;
		_globalSortOrder = globalSortOrder;
	}
	
	return self;
}

-(void)dealloc
{
    [_renderState release]; _renderState = nil;
    
    [super dealloc];
}

-(NSInteger)globalSortOrder
{
	return _globalSortOrder;
}

-(void)batch:(NSUInteger)count
{
	_count += count;
}

-(void)invokeOnRenderer:(CCRenderer *)renderer
{NSAssert(NO, @"Must be overridden.");}

@end


#pragma mark Custom Block Command.
@interface CCRenderCommandCustom : NSObject<CCRenderCommand> @end
@implementation CCRenderCommandCustom {
	void (^_block)();
	NSString *_debugLabel;
	
	NSInteger _globalSortOrder;
}

-(instancetype)initWithBlock:(void (^)())block debugLabel:(NSString *)debugLabel globalSortOrder:(NSInteger)globalSortOrder
{
	if((self = [super init])){
		_block = [block copy];
		_debugLabel = [debugLabel retain];
		
		_globalSortOrder = globalSortOrder;
	}
	
	return self;
}

-(void)dealloc
{
    [_block release]; _block = nil;
    [_debugLabel release]; _debugLabel = nil;
    
    [super dealloc];
}

-(NSInteger)globalSortOrder
{
	return _globalSortOrder;
}

-(void)invokeOnRenderer:(CCRenderer *)renderer
{
	CCRENDERER_DEBUG_PUSH_GROUP_MARKER(_debugLabel);
	
    CCRendererBindBuffers(renderer, NO, 0);
	_block();
	
	CCRENDERER_DEBUG_POP_GROUP_MARKER();
}

@end


#pragma mark Rendering group command.

static void
SortQueue(NSMutableArray *queue)
{
	[queue sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id<CCRenderCommand> obj1, id<CCRenderCommand> obj2) {
		NSInteger sort1 = obj1.globalSortOrder;
		NSInteger sort2 = obj2.globalSortOrder;
		
		if(sort1 < sort2) return NSOrderedAscending;
		if(sort1 > sort2) return NSOrderedDescending;
		return NSOrderedSame;
	}];
}

@interface CCRenderCommandGroup : NSObject<CCRenderCommand> @end
@implementation CCRenderCommandGroup {
	NSMutableArray *_queue;
	NSString *_debugLabel;
	
	NSInteger _globalSortOrder;
}

-(instancetype)initWithQueue:(NSMutableArray *)queue debugLabel:(NSString *)debugLabel globalSortOrder:(NSInteger)globalSortOrder
{
	if((self = [super init])){
		_queue = [queue retain];
		_debugLabel = [debugLabel retain];
		
		_globalSortOrder = globalSortOrder;
	}
	
	return self;
}

-(void)dealloc
{
    [_queue release]; _queue = nil;
    [_debugLabel release]; _debugLabel = nil;
    
    [super dealloc];
}

-(void)invokeOnRenderer:(CCRenderer *)renderer
{
	SortQueue(_queue);
	
	CCRENDERER_DEBUG_PUSH_GROUP_MARKER(_debugLabel);
	for(id<CCRenderCommand> command in _queue) [command invokeOnRenderer:renderer];
	CCRENDERER_DEBUG_POP_GROUP_MARKER();
}

-(NSInteger)globalSortOrder
{
	return _globalSortOrder;
}

@end


#pragma mark Render Queue


@implementation CCRenderer

-(instancetype)init
{
	if((self = [super init])){
		_buffers = [[CCGraphicsBufferBindingsMetal alloc] init];
				
		_threadsafe = YES;
		_queue = [[NSMutableArray alloc] init];
	}
	
	return self;
}

-(void)dealloc
{
    [_buffers release]; _buffers = nil;
    [_framebuffer release]; _framebuffer = nil;
    
    [_globalShaderUniforms release]; _globalShaderUniforms = nil;
    [_globalShaderUniformBufferOffsets release]; _globalShaderUniformBufferOffsets = nil;
    
    [_queue release]; _queue = nil;
    [_queueStack release]; _queueStack = nil;
    
    [super dealloc];
}

-(void)invalidateState
{
	_lastDrawCommand = nil;
	_renderState = nil;
	_buffersBound = NO;
}

static NSString *CURRENT_RENDERER_KEY = @"CCRendererCurrent";

+(instancetype)currentRenderer
{
	return [NSThread currentThread].threadDictionary[CURRENT_RENDERER_KEY];
}

+(void)bindRenderer:(CCRenderer *)renderer
{
	if(renderer){
		[NSThread currentThread].threadDictionary[CURRENT_RENDERER_KEY] = renderer;
	} else {
		[[NSThread currentThread].threadDictionary removeObjectForKey:CURRENT_RENDERER_KEY];
	}
}

-(void)prepareWithProjection:(const GLKMatrix4 *)projection framebuffer:(CCFrameBufferObject *)framebuffer
{
	NSAssert(framebuffer, @"Framebuffer cannot be nil.");
	Director *director = [Director currentDirector];
	
	// Copy in the globals from the director.
	NSMutableDictionary *globalShaderUniforms = [director.globalShaderUniforms mutableCopy];
	
	// Group all of the standard globals into one value.
	// Used by Metal, will be used eventually by a GL3 renderer.
	CCGlobalUniforms globals = {};
	
	globals.projection = *projection;
	globals.projectionInv = GLKMatrix4Invert(globals.projection, NULL);
	globalShaderUniforms[CCShaderUniformProjection] = [NSValue valueWithGLKMatrix4:globals.projection];
	globalShaderUniforms[CCShaderUniformProjectionInv] = [NSValue valueWithGLKMatrix4:globals.projectionInv];
	
	CGSize pixelSize = framebuffer.sizeInPixels;
	globals.viewSizeInPixels = GLKVector2Make(pixelSize.width, pixelSize.height);
	globalShaderUniforms[CCShaderUniformViewSizeInPixels] = [NSValue valueWithGLKVector2:globals.viewSizeInPixels];
	
	float coef = 1.0/framebuffer.contentScale;
	globals.viewSize = GLKVector2Make(coef*pixelSize.width, coef*pixelSize.height);
	globalShaderUniforms[CCShaderUniformViewSize] = [NSValue valueWithGLKVector2:globals.viewSize];
	
    float t = 0.0f;
	globals.time = GLKVector4Make(t, t/2.0f, t/4.0f, t/8.0f);
	globals.sinTime = GLKVector4Make(sinf(t*2.0f), sinf(t), sinf(t/2.0f), sinf(t/4.0f));
	globals.cosTime = GLKVector4Make(cosf(t*2.0f), cosf(t), cosf(t/2.0f), cosf(t/4.0f));
	globalShaderUniforms[CCShaderUniformTime] = [NSValue valueWithGLKVector4:globals.time];
	globalShaderUniforms[CCShaderUniformSinTime] = [NSValue valueWithGLKVector4:globals.sinTime];
	globalShaderUniforms[CCShaderUniformCosTime] = [NSValue valueWithGLKVector4:globals.cosTime];
	
	globals.random01 = GLKVector4Make(CCRANDOM_0_1(), CCRANDOM_0_1(), CCRANDOM_0_1(), CCRANDOM_0_1());
	globalShaderUniforms[CCShaderUniformRandom01] = [NSValue valueWithGLKVector4:globals.random01];
	
	globalShaderUniforms[CCShaderUniformDefaultGlobals] = [NSValue valueWithBytes:&globals objCType:@encode(CCGlobalUniforms)];
	
    [_globalShaderUniforms release];
	_globalShaderUniforms = globalShaderUniforms;
		
	// If we are using a uniform buffer (ex: Metal) copy the global uniforms into it.
	CCGraphicsBuffer *uniformBuffer = _buffers->_uniformBuffer;
	if(uniformBuffer){
		NSMutableDictionary *offsets = [[NSMutableDictionary alloc] init];
		size_t offset = 0;
		
		for(NSString *name in _globalShaderUniforms){
			NSValue *value = _globalShaderUniforms[name];
			
			// Round up to the next multiple of 16 since Metal types have an alignment of 16 bytes at most.
			size_t alignedBytes = ((value.CCRendererSizeOf - 1) | 0xF) + 1;
			
			void * buff = CCGraphicsBufferPushElements(uniformBuffer, alignedBytes);
			[value getValue:buff];
			offsets[name] = @(offset);
			
			offset += alignedBytes;
		}
		
        [_globalShaderUniformBufferOffsets release];
		_globalShaderUniformBufferOffsets = offsets;
	}
	
    [_framebuffer autorelease];
	_framebuffer = framebuffer;
}

//Implemented in CCNoARC.m
//-(void)bindBuffers:(BOOL)bind
//-(void)setRenderState:(CCRenderState *)renderState
//-(CCRenderBuffer)enqueueTriangles:(NSUInteger)triangleCount andVertexes:(NSUInteger)vertexCount withState:(CCRenderState *)renderState globalSortOrder:(NSInteger)globalSortOrder;
//-(CCRenderBuffer)enqueueLines:(NSUInteger)lineCount andVertexes:(NSUInteger)vertexCount withState:(CCRenderState *)renderState globalSortOrder:(NSInteger)globalSortOrder;

-(void)enqueueClear:(MTLLoadAction)mask color:(GLKVector4)color4 globalSortOrder:(NSInteger)globalSortOrder
{
	// If a clear is the very first command, then handle it specially.
	if(globalSortOrder == NSIntegerMin && _queue.count == 0 && _queueStack.count == 0){
		_clearMask = mask;
		_clearColor = color4;
	}
}

-(void)enqueueBlock:(void (^)())block globalSortOrder:(NSInteger)globalSortOrder debugLabel:(NSString *)debugLabel threadSafe:(BOOL)threadsafe
{
    CCRenderCommandCustom *command = [[CCRenderCommandCustom alloc] initWithBlock:block debugLabel:debugLabel globalSortOrder:globalSortOrder];
	[_queue addObject:command];
    [command release];
    
	_lastDrawCommand = nil;
	
	if(!threadsafe) _threadsafe = NO;
}

-(void)enqueueMethod:(SEL)selector target:(id)target
{
    [self enqueueBlock:^{
        typedef void (*Func)(id, SEL);
        ((Func)objc_msgSend)(target, selector);
    } globalSortOrder:0 debugLabel:NSStringFromSelector(selector) threadSafe:NO];
}

-(void)enqueueRenderCommand: (id<CCRenderCommand>) renderCommand {
	[_queue addObject: renderCommand];
	_lastDrawCommand = nil;
	
	_threadsafe = NO;
}

-(void)pushGroup;
{
	if(_queueStack == nil){
		// Allocate the stack lazily.
		_queueStack = [[NSMutableArray alloc] init];
	}
	
	[_queueStack addObject:_queue];
    
    [_queue release];
	_queue = [[NSMutableArray alloc] init];
    
	_lastDrawCommand = nil;
}

-(void)popGroupWithDebugLabel:(NSString *)debugLabel globalSortOrder:(NSInteger)globalSortOrder
{
	NSAssert(_queueStack.count > 0, @"Render queue stack underflow. (Unmatched pushQueue/popQueue calls.)");
	
	NSMutableArray *groupQueue = _queue;
    
	_queue = [[_queueStack lastObject] retain];
	[_queueStack removeLastObject];
	
    CCRenderCommandGroup *command = [[CCRenderCommandGroup alloc] initWithQueue:groupQueue debugLabel:debugLabel globalSortOrder:globalSortOrder];
    [groupQueue release];
    
	[_queue addObject:command];
    [command release];
    
	_lastDrawCommand = nil;
}

-(void)flush
{
	CCRENDERER_DEBUG_PUSH_GROUP_MARKER(@"CCRenderer: Flush");
	
	[_framebuffer bindWithClear:_clearMask color:_clearColor];
	
	// Commit the buffers.
	[_buffers commit];
		
	// Execute the rendering commands.
	SortQueue(_queue);
	for(id<CCRenderCommand> command in _queue) [command invokeOnRenderer:self];
    CCRendererBindBuffers(self, NO, 0);
	
	[_queue removeAllObjects];
	
	// Prepare the buffers.
	[_buffers prepare];
	
	CCRENDERER_DEBUG_POP_GROUP_MARKER();
	CCRENDERER_DEBUG_CHECK_ERRORS();
	
	// Reset the renderer's state.
	[self invalidateState];
	_threadsafe = YES;
	_framebuffer = nil;
	_clearMask = 0;
}

@end
