#import "ImageViewerViewController.h"

@interface SCImageViewerViewController () <UIScrollViewDelegate>
@end

@implementation SCImageViewerViewController {
    NSString *_imagePath;
    UIScrollView *_scrollView;
    UIImageView *_imageView;
}

- (instancetype)initWithImagePath:(NSString *)imagePath
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _imagePath = [imagePath copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = _imagePath.lastPathComponent ?: @"Image";

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = 8.0;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.alwaysBounceHorizontal = YES;
    _scrollView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:_scrollView];

    _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.userInteractionEnabled = YES;
    [_scrollView addSubview:_imageView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [_scrollView addGestureRecognizer:doubleTap];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(loadImage)];
    [self loadImage];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self layoutImageView];
}

- (void)loadImage
{
    UIImage *image = [UIImage imageWithContentsOfFile:_imagePath];
    if (!image) {
        _imageView.image = nil;
        _scrollView.contentSize = CGSizeZero;
        [self showMessageWithTitle:@"Image" message:@"Could not open image file."];
        return;
    }
    _scrollView.zoomScale = 1.0;
    _imageView.image = image;
    [self layoutImageView];
}

- (void)layoutImageView
{
    UIImage *image = _imageView.image;
    if (!image) return;

    CGSize boundsSize = _scrollView.bounds.size;
    if (boundsSize.width <= 0.0 || boundsSize.height <= 0.0) return;

    CGFloat imageRatio = image.size.width / MAX(image.size.height, 1.0);
    CGFloat boundsRatio = boundsSize.width / MAX(boundsSize.height, 1.0);
    CGSize fittedSize = CGSizeZero;
    if (imageRatio > boundsRatio) {
        fittedSize.width = boundsSize.width;
        fittedSize.height = boundsSize.width / MAX(imageRatio, 0.001);
    } else {
        fittedSize.height = boundsSize.height;
        fittedSize.width = boundsSize.height * imageRatio;
    }

    CGFloat x = MAX((boundsSize.width - fittedSize.width) / 2.0, 0.0);
    CGFloat y = MAX((boundsSize.height - fittedSize.height) / 2.0, 0.0);
    _imageView.frame = CGRectMake(x, y, fittedSize.width, fittedSize.height);
    _scrollView.contentSize = boundsSize;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    (void)scrollView;
    return _imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    CGSize boundsSize = scrollView.bounds.size;
    CGRect frame = _imageView.frame;
    frame.origin.x = frame.size.width < boundsSize.width ? (boundsSize.width - frame.size.width) / 2.0 : 0.0;
    frame.origin.y = frame.size.height < boundsSize.height ? (boundsSize.height - frame.size.height) / 2.0 : 0.0;
    _imageView.frame = frame;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer
{
    if (_scrollView.zoomScale > 1.0) {
        [_scrollView setZoomScale:1.0 animated:YES];
        return;
    }
    CGPoint point = [recognizer locationInView:_imageView];
    CGFloat newScale = MIN(_scrollView.maximumZoomScale, 3.0);
    CGSize size = _scrollView.bounds.size;
    CGRect rect = CGRectMake(point.x - size.width / (newScale * 2.0),
                             point.y - size.height / (newScale * 2.0),
                             size.width / newScale,
                             size.height / newScale);
    [_scrollView zoomToRect:rect animated:YES];
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
