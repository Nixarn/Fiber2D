/*
 * Cocos2D-SpriteBuilder: http://cocos2d.spritebuilder.com
 *
 * Copyright (c) 2008-2010 Ricardo Quesada
 * Copyright (c) 2011 Zynga Inc.
 * Copyright (c) 2013-2014 Cocos2D Authors
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
 *
 */

#import <objc/message.h>

#import "ccMacros.h"

#import "CCTextureCache.h"

#import "CCTexture_Private.h"
#import "CCSetup.h"
#import "Fiber2D-Swift.h"
#import "CCFileLocator.h"
#import "CCFile_Private.h"

@implementation CCTextureCache

#pragma mark TextureCache - Alloc, Init & Dealloc
static CCTextureCache *sharedTextureCache;

+ (CCTextureCache *)sharedTextureCache
{
	if (!sharedTextureCache)
		sharedTextureCache = [[self alloc] init];

	return sharedTextureCache;
}

+(id)alloc
{
	NSAssert(sharedTextureCache == nil, @"Attempted to allocate a second instance of a singleton.");
	return [super alloc];
}

+(void)purgeSharedTextureCache
{
	sharedTextureCache = nil;
}

-(id) init
{
	if( (self=[super init]) ) {
		_textures = [NSMutableDictionary dictionaryWithCapacity: 10];
		
		// init "global" stuff
		_loadingQueue = dispatch_queue_create("org.cocos2d.texturecacheloading", NULL);
		_dictQueue = dispatch_queue_create("org.cocos2d.texturecachedict", NULL);
		
        return self;

	}

	return self;
}

- (NSString*) description
{
	__block NSString *desc = nil;
	dispatch_sync(_dictQueue, ^{
		desc = [NSString stringWithFormat:@"<%@ = %p | num of textures =  %lu | keys: %@>",
			[self class],
			self,
			(unsigned long)[_textures count],
			[_textures allKeys]
			];
	});
	return desc;
}

-(void) dealloc
{
	CCLOGINFO(@"cocos2d: deallocing %@", self);
    
	sharedTextureCache = nil;
    
	// dispatch_release(_loadingQueue);
	// dispatch_release(_dictQueue);
    
}

#pragma mark TextureCache - Add Images

// TODO temporary method.
-(void)addTexture:(CCTexture *)texture forKey:(NSString *)key
{
    dispatch_sync(_dictQueue, ^{
        NSAssert(_textures[key] == nil, @"Texture is already in the cache?");
        _textures[key] = texture;
    });
}

-(CCTexture*) addImage: (NSString*) path
{
	NSAssert(path != nil, @"TextureCache: fileimage MUST not be nil");

	__block CCTexture * tex = nil;

	dispatch_sync(_dictQueue, ^{
		tex = [_textures objectForKey: path];
	});

	if( ! tex ) {
        CCFile *file = [[CCFileLocator sharedFileLocator] fileNamedWithResolutionSearch:path error:nil];
        
		if( ! file ) {
			CCLOG(@"cocos2d: Couldn't find file:%@", path);
			return nil;
		}

		NSString *lowerCase = [file.absoluteFilePath lowercaseString];

		// All images are handled by CoreGraphics except PVR files which are handled by Cocos2D.

        if([lowerCase hasSuffix:@".pvr"] || [lowerCase hasSuffix:@".pvr.gz"] || [lowerCase hasSuffix:@".pvr.ccz"]){
            tex = [self addPVRImage:path];
        } else {
            Image* image = [[Image alloc] initWithFile: file];
            tex = [[CCTexture alloc] initWithImage:image options:nil];

            if(tex){
                dispatch_sync(_dictQueue, ^{
                    [_textures setObject: tex forKey:path];
                    CCLOGINFO(@"Texture %@ cached: %p", path, tex);
                });
            } else {
                CCLOG(@"cocos2d: Couldn't create texture for file:%@ in CCTextureCache", path);
            }
        }
	}

	return((id)tex.proxy);
}

#pragma mark TextureCache - Remove

-(void) removeAllTextures
{
	dispatch_sync(_dictQueue, ^{
		[_textures removeAllObjects];
	});
}

-(void) removeUnusedTextures
{
    dispatch_sync(_dictQueue, ^{
        NSArray *keys = [_textures allKeys];
        for(id key in keys)
        {
            CCTexture *texture = [_textures objectForKey:key];
            CCLOGINFO(@"texture: %@", texture);
            // If the weakly retained proxy object is nil, then the texture is unreferenced.
            if (!texture.hasProxy)
            {
                CCLOGINFO(@"cocos2d: CCTextureCache: removing unused texture: %@", key);
                [_textures removeObjectForKey:key];
            }
        }
        CCLOGINFO(@"Purge complete.");
    });
}

-(void) removeTexture: (CCTexture*) tex
{
	if( ! tex )
		return;

	dispatch_sync(_dictQueue, ^{
		NSArray *keys = [_textures allKeysForObject:tex];

		for( NSUInteger i = 0; i < [keys count]; i++ )
			[_textures removeObjectForKey:[keys objectAtIndex:i]];
	});
}

-(void) removeTextureForKey:(NSString*)name
{
	if( ! name )
		return;

	dispatch_sync(_dictQueue, ^{
		[_textures removeObjectForKey:name];
	});
}

#pragma mark TextureCache - Get
- (CCTexture *)textureForKey:(NSString *)key
{
	__block CCTexture *tex = nil;

	dispatch_sync(_dictQueue, ^{
		tex = [_textures objectForKey:key];
	});

	return((id)tex.proxy);
}

@end


@implementation CCTextureCache (PVRSupport)

-(CCTexture*) addPVRImage:(NSString*)path
{
	NSAssert(path != nil, @"TextureCache: fileimage MUST not be nill");

	__block CCTexture * tex;
	
	dispatch_sync(_dictQueue, ^{
		tex = [_textures objectForKey:path];
	});

	if(tex) {
		return((id)tex.proxy);
	}
    
	tex = [[CCTexture alloc] initPVRWithCCFile:[[CCFileLocator sharedFileLocator] fileNamedWithResolutionSearch:path error:nil] options:nil];
	if( tex ){
		dispatch_sync(_dictQueue, ^{
			[_textures setObject: tex forKey:path];
		});
	}else{
		CCLOG(@"cocos2d: Couldn't add PVRImage:%@ in CCTextureCache",path);
	}

	return((id)tex.proxy);
}

@end


@implementation CCTextureCache (Debug)

-(void) dumpCachedTextureInfo
{
	__block NSUInteger count = 0;

	dispatch_sync(_dictQueue, ^{
		for (NSString* texKey in _textures) {
			CCTexture* tex = [_textures objectForKey:texKey];
			count++;
			NSLog( @"cocos2d: \"%@\"\t%lu x %lu",
				  texKey,
				  (long)tex.sizeInPixels.width,
				  (long)tex.sizeInPixels.height);
		}
	});
	NSLog( @"cocos2d: CCTextureCache dumpDebugInfo:\t%ld textures", (long)count);
}

@end
