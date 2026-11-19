// Simulator diagnostics: no private-filter/GPU claims.
static NSDictionary *labelConfiguration(UILabel *l) {
    NSMutableArray *runs=[NSMutableArray array];
    [l.attributedText enumerateAttributesInRange:NSMakeRange(0,l.attributedText.length) options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        (void)stop;
        NSMutableDictionary *d=[NSMutableDictionary dictionary];
        d[@"range"]=NSStringFromRange(range);
        for (NSString *key in attrs) d[key]=[attrs[key] description];
        NSTextAttachment *a=attrs[NSAttachmentAttributeName];
        if (a) { d[@"attachmentBounds"]=NSStringFromCGRect(a.bounds); d[@"attachmentImageSize"]=NSStringFromCGSize(a.image.size); d[@"attachmentImageScale"]=@(a.image.scale); d[@"attachmentRenderingMode"]=@(a.image.renderingMode); }
        [runs addObject:d];
    }];
    return @{@"text":l.text?:@"<nil>",@"font":l.font.description?:@"<nil>",
        @"bounds":NSStringFromCGRect(l.bounds),@"frame":NSStringFromCGRect(l.frame),
        @"contentScaleFactor":@(l.contentScaleFactor),@"layerContentsScale":@(l.layer.contentsScale),
        @"alignment":@(l.textAlignment),@"lines":@(l.numberOfLines),@"lineBreak":@(l.lineBreakMode),
        @"adjustsFont":@(l.adjustsFontSizeToFitWidth),@"minimumScale":@(l.minimumScaleFactor),
        @"baseline":@(l.baselineAdjustment),@"semantic":@(l.semanticContentAttribute),
        @"textColor":l.textColor.description?:@"<nil>",@"attributedString":l.attributedText.string?:@"<nil>",@"runs":runs};
}
static void saveParityDiagnostic(NSString *name, UIImage *actual, UIImage *expected, UILabel *label, UILabel *reference, CGFloat scale) {
    NSString *root=NSProcessInfo.processInfo.environment[@"SBCPU_TEXT_INVERT_DIAGNOSTICS"]?:NSTemporaryDirectory();
    NSString *dir=[root stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    [UIImagePNGRepresentation(actual) writeToFile:[dir stringByAppendingPathComponent:@"actual.png"] atomically:YES];
    [UIImagePNGRepresentation(expected) writeToFile:[dir stringByAppendingPathComponent:@"expected.png"] atomically:YES];
    CALayer *mask=label.layer.sublayers.lastObject.mask;
    UILabel *glyph=[mask valueForKey:@"glyphLabel"];
    NSDictionary *d=@{@"scale":@(scale),@"actualImage":actual.description?:@"nil",@"expectedImage":expected.description?:@"nil",@"label":labelConfiguration(label),@"productionGlyph":glyph?labelConfiguration(glyph):@{},@"reference":labelConfiguration(reference)};
    NSData *json=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:NULL];
    [json writeToFile:[dir stringByAppendingPathComponent:@"configuration.json"] atomically:YES];
    fprintf(stderr,"PIXEL DIAGNOSTIC %s\n",dir.UTF8String);
}
