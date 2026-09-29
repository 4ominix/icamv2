#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

#define PREF_PATH @"/var/mobile/Library/Preferences/com.weat.fakecamera.plist"
#define MEDIA_STORAGE_DIR @"/var/mobile/Documents/FakeCamera"

@interface FakeCameraPrefsRootListController : PSListController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, assign) NSInteger currentPickingType; // 1: Image, 2: Video
@end

@implementation FakeCameraPrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)ensureDirectoryExists {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:MEDIA_STORAGE_DIR]) {
        [fm createDirectoryAtPath:MEDIA_STORAGE_DIR withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0777} error:nil];
    }
}

- (void)savePreferenceValue:(id)value forKey:(NSString *)key {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREF_PATH] ?: [NSMutableDictionary dictionary];
    prefs[key] = value;
    [prefs writeToFile:PREF_PATH atomically:YES];
    
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.weat.fakecamera/prefsupdated"),
        NULL,
        NULL,
        YES
    );
}

- (void)selectImageFromLibrary {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
                self.currentPickingType = 1;
                UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                picker.delegate = self;
                picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                picker.mediaTypes = @[@"public.image"];
                picker.allowsEditing = NO;
                [self presentViewController:picker animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Quyền Truy Cập"
                                                                               message:@"Vui lòng cấp quyền truy cập Thư viện ảnh trong Cài Đặt."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

- (void)selectVideoFromLibrary {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
                self.currentPickingType = 2;
                UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                picker.delegate = self;
                picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                picker.mediaTypes = @[@"public.movie"];
                picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
                picker.allowsEditing = NO;
                [self presentViewController:picker animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Quyền Truy Cập"
                                                                               message:@"Vui lòng cấp quyền truy cập Thư viện ảnh trong Cài Đặt."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [self ensureDirectoryExists];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (self.currentPickingType == 1) {
        UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
        if (selectedImage) {
            NSString *targetPath = [MEDIA_STORAGE_DIR stringByAppendingPathComponent:@"fake_image.jpg"];
            NSData *jpegData = UIImageJPEGRepresentation(selectedImage, 0.95);
            [jpegData writeToFile:targetPath atomically:YES];
            [fm setAttributes:@{NSFilePosixPermissions: @0777} ofItemAtPath:targetPath error:nil];
            
            [self savePreferenceValue:targetPath forKey:@"imagePath"];
            [self savePreferenceValue:@(1) forKey:@"mediaType"];
            
            [self reloadSpecifiers];
            
            UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:@"Thành Công"
                                                                              message:@"Đã chọn và đồng bộ ảnh vào hệ thống fake camera!"
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [doneAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [picker dismissViewControllerAnimated:YES completion:^{
                [self presentViewController:doneAlert animated:YES completion:nil];
            }];
            return;
        }
    } else if (self.currentPickingType == 2) {
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        if (videoURL) {
            NSString *targetPath = [MEDIA_STORAGE_DIR stringByAppendingPathComponent:@"fake_video.mp4"];
            if ([fm fileExistsAtPath:targetPath]) {
                [fm removeItemAtPath:targetPath error:nil];
            }
            NSError *copyError = nil;
            [fm copyItemAtURL:videoURL toURL:[NSURL fileURLWithPath:targetPath] error:&copyError];
            [fm setAttributes:@{NSFilePosixPermissions: @0777} ofItemAtPath:targetPath error:nil];
            
            [self savePreferenceValue:targetPath forKey:@"videoPath"];
            [self savePreferenceValue:@(2) forKey:@"mediaType"];
            
            [self reloadSpecifiers];
            
            UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:@"Thành Công"
                                                                              message:@"Đã chọn và đồng bộ video vào hệ thống fake camera!"
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [doneAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [picker dismissViewControllerAnimated:YES completion:^{
                [self presentViewController:doneAlert animated:YES completion:nil];
            }];
            return;
        }
    }
    
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end
