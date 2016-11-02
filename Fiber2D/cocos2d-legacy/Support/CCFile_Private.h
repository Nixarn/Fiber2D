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


#import "CCFile.h"

@interface NSInputStream (DATA_HINT)
-(NSData *)loadDataWithSizeHint:(NSUInteger)sizeHint error:(NSError **)error;
@end


// Return an opened input stream to read from.
// May be called more than once if the file is rewound.
typedef NSInputStream *(^CCStreamedImageSourceStreamBlock)();

// Adapter class that creates a CGImage source from an NSInputStream.
@interface CCStreamedImageSource : NSObject
-(instancetype)initWithStreamBlock:(CCStreamedImageSourceStreamBlock)streamBlock;
-(CGDataProviderRef)createCGDataProvider;
-(CGImageSourceRef)createCGImageSource;
@end


@interface CCFile()

@property (nonatomic, readonly) CGFloat autoScaleFactor;
@property (nonatomic, assign, readwrite) BOOL useUIScale;

@end


@interface CCFile(Private)

@property(nonatomic, assign) CGFloat contentScale;
@property(nonatomic, assign) BOOL hasResolutionTag;


-(instancetype)initWithName:(NSString *)name url:(NSURL *)url contentScale:(CGFloat)contentScale tagged:(BOOL)tagged;
-(CGImageSourceRef)createCGImageSource;


@end
