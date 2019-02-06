use std::error::Error;
use std::time;

use aws_lambda_events::event::s3::{S3Event, S3EventRecord};
use aws_lambda_events::event::sqs::SqsEvent;
use backoff::{ExponentialBackoff, Operation};
use lambda_runtime::{error::HandlerError, lambda, Context};
use log::{error, info, warn};
use rusoto_core::Region;
use rusoto_lambda::{Lambda, LambdaClient, UpdateFunctionCodeRequest};
use serde_json;
use simple_logger;

fn process_event(event: &S3EventRecord) -> Result<(), Box<dyn Error>> {
    let region = event
        .aws_region
        .as_ref()
        .ok_or("No region specified.".to_owned())?
        .parse::<Region>()?;
    let bucket = event
        .s3
        .bucket
        .name
        .as_ref()
        .ok_or("No bucket specified.".to_owned())?
        .to_string();
    let key = event
        .s3
        .object
        .key
        .as_ref()
        .ok_or("No Key specified.".to_owned())?
        .to_string();
    let version_id = event
        .s3
        .object
        .version_id
        .as_ref()
        .ok_or("No Version Specified.".to_owned())?
        .to_string();
    let function = key.clone();

    let client = LambdaClient::new(region);

    let mut op = || {
        let output = client
            .update_function_code(UpdateFunctionCodeRequest {
                function_name: function.clone(),
                s3_bucket: Some(bucket.clone()),
                s3_key: Some(key.clone()),
                s3_object_version: Some(version_id.clone()),
                ..Default::default()
            })
            .sync()?;

        Ok(output)
    };

    let mut backoff = ExponentialBackoff {
        max_elapsed_time: Some(time::Duration::from_secs(60)),
        ..Default::default()
    };

    op.retry_notify(&mut backoff, |err, dur| {
        warn!(
            "Error occured updating {:?} at {:?}: {:?}",
            function, dur, err
        )
    })?;

    info!("Updated code for Lambda function: {:?}", function);

    Ok(())
}

fn handler(e: SqsEvent, _c: Context) -> Result<(), HandlerError> {
    for message in &e.records {
        if let Some(body) = &message.body {
            let res: serde_json::Result<S3Event> = serde_json::from_str(&body);
            match res {
                Ok(e) => {
                    for event in &e.records {
                        if let Err(e) = process_event(event) {
                            error!("Could not process S3 event ({:?}: {:?}", e, event);
                        }
                    }
                }
                Err(e) => error!("Could not parse SQS Body ({:?}): {:?}", e, body),
            }
        }
    }

    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    simple_logger::init_with_level(log::Level::Info)?;

    lambda!(handler);

    Ok(())
}
